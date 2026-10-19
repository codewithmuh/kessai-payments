"""Runtime contract: probes, metrics, request IDs, JSON errors, logs, configuration, shutdown."""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest
from django.db import OperationalError, connection
from rest_framework.test import APIClient

from core import lifecycle
from core.logs import JsonFormatter, RequestIdFilter, request_id_var
from core.metrics import render_latest

SERVICE_DIR = Path(__file__).resolve().parents[1]


@pytest.fixture
def client() -> APIClient:
    return APIClient()


def test_healthz_never_touches_the_database(client: APIClient) -> None:
    # No `db` fixture: pytest-django would fail this test on any query.
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


@pytest.mark.django_db
def test_readyz_when_the_database_answers(client: APIClient) -> None:
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_readyz_fails_during_shutdown(client: APIClient) -> None:
    lifecycle.mark_shutting_down()
    response = client.get("/readyz")
    assert response.status_code == 503
    assert response.json() == {"status": "shutting_down"}


def test_readyz_fails_when_the_database_never_answered(
    client: APIClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    # A new pod that cannot reach the database (a wrong DATABASE_URL, say) takes no traffic.
    class DownConnection:
        def cursor(self) -> Any:
            raise OperationalError("connection refused")

    monkeypatch.setattr("core.middleware.connection", DownConnection())
    response = client.get("/readyz")
    assert response.status_code == 503
    assert response.json() == {"status": "database_unreachable"}


@pytest.mark.django_db
def test_readyz_rides_out_a_short_outage(
    client: APIClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    # The database answered once, then fails: inside the grace window the pod stays ready, so
    # requests reach Django and get 503 + Retry-After instead of connection errors.
    assert client.get("/readyz").status_code == 200

    class DownConnection:
        def cursor(self) -> Any:
            raise OperationalError("server closed the connection unexpectedly")

    monkeypatch.setattr("core.middleware.connection", DownConnection())
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json()["status"] == "degraded"
    monkeypatch.setattr("core.middleware.connection", connection)


def test_probes_and_metrics_skip_the_host_check(client: APIClient) -> None:
    # The kubelet and Prometheus call the pod IP, which is not in ALLOWED_HOSTS.
    assert client.get("/healthz", HTTP_HOST="10.1.2.3:8000").status_code == 200
    assert client.get("/metrics", HTTP_HOST="10.1.2.3:8000").status_code == 200


def test_api_requests_must_use_an_allowed_host(client: APIClient) -> None:
    response = client.get("/v1/openapi.yaml", HTTP_HOST="evil.example")
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "bad_request"


def test_metrics_label_routes_by_pattern_not_raw_path(client: APIClient) -> None:
    client.get("/healthz")
    client.get("/v1/openapi.yaml")
    client.get("/no/such/path-12345")
    body = client.get("/metrics").content.decode()
    assert 'http_requests_total{method="GET",route="/healthz",status="200"}' in body
    assert 'route="/v1/openapi.yaml",status="200"' in body
    assert 'route="unmatched"' in body
    assert "path-12345" not in body  # raw paths never become label values
    assert 'http_request_duration_seconds_bucket{le="0.3"' in body


def test_unknown_methods_share_one_label(client: APIClient) -> None:
    client.generic("BREW", "/healthz")
    assert 'method="OTHER"' in client.get("/metrics").content.decode()


def test_metrics_in_multiprocess_mode(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("PROMETHEUS_MULTIPROC_DIR", str(tmp_path))
    body, content_type = render_latest()
    assert content_type.startswith("text/plain")
    assert isinstance(body, bytes)


def test_request_id_is_echoed_or_generated(client: APIClient) -> None:
    assert client.get("/healthz", HTTP_X_REQUEST_ID="req-123").headers["X-Request-ID"] == "req-123"
    generated = client.get("/healthz").headers["X-Request-ID"]
    assert len(generated) == 32


def test_untrusted_request_id_is_replaced(client: APIClient) -> None:
    response = client.get("/healthz", HTTP_X_REQUEST_ID='bad"id\nINJECTED')
    assert response.headers["X-Request-ID"] != 'bad"id\nINJECTED'
    assert len(response.headers["X-Request-ID"]) == 32


def test_access_log_carries_request_id(client: APIClient, caplog: pytest.LogCaptureFixture) -> None:
    with caplog.at_level(logging.INFO, logger="kessai.http"):
        client.get("/v1/openapi.yaml", HTTP_X_REQUEST_ID="trace-me")
    lines = [r for r in caplog.records if r.name == "kessai.http"]
    assert lines
    assert lines[-1].__dict__["route"] == "/v1/openapi.yaml"
    assert lines[-1].__dict__["status"] == 200
    formatted = json.loads(JsonFormatter().format(lines[-1]))
    assert formatted["msg"] == "request"


def test_probes_are_not_access_logged(client: APIClient, caplog: pytest.LogCaptureFixture) -> None:
    with caplog.at_level(logging.INFO, logger="kessai.http"):
        client.get("/healthz")
    assert not [r for r in caplog.records if r.name == "kessai.http"]


def test_unknown_path_is_a_json_404(client: APIClient) -> None:
    response = client.get("/nope")
    assert response.status_code == 404
    assert response.json() == {"error": {"code": "not_found", "message": "No such endpoint."}}


def test_security_headers(client: APIClient) -> None:
    response = client.get("/v1/openapi.yaml")
    assert response.status_code == 200
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["Referrer-Policy"] == "no-referrer"
    assert response.headers["X-Frame-Options"] == "DENY"


def test_json_formatter_and_request_id_filter() -> None:
    token = request_id_var.set("r1")
    try:
        record = logging.makeLogRecord({"msg": "hi %s", "args": ("there",), "levelname": "INFO"})
        RequestIdFilter().filter(record)
    finally:
        request_id_var.reset(token)
    try:
        raise ValueError("x")
    except ValueError:
        record.exc_info = sys.exc_info()
    out = json.loads(JsonFormatter().format(record))
    assert out["msg"] == "hi there"
    assert out["request_id"] == "r1"
    assert out["level"] == "info"
    assert "ValueError" in out["exc"]


def _import_settings(
    env: dict[str, str], code: str = "import config.settings"
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603 (the code is one of this file's constant snippets)
        [sys.executable, "-c", code],
        env={"PATH": os.environ.get("PATH", ""), "PYTHONPATH": str(SERVICE_DIR / "src"), **env},
        capture_output=True,
        text=True,
        check=False,
    )


GOOD_ENV = {
    "DJANGO_SECRET_KEY": "x" * 50,
    "DATABASE_URL": "postgres://u:p@localhost:5432/kessai",
}


def test_settings_refuse_to_start_without_secrets() -> None:
    result = _import_settings({})
    assert result.returncode != 0
    assert (
        "Missing required environment variables: DATABASE_URL, DJANGO_SECRET_KEY" in result.stderr
    )


def test_settings_load_with_every_secret() -> None:
    assert _import_settings(GOOD_ENV).returncode == 0


_PRINT_DATABASE_SETTINGS = (
    "from config import settings as s; "
    "print(s.DATABASES['default']['OPTIONS']['connect_timeout'], s.DB_RETRY_AFTER_SECONDS, "
    "s.READINESS_DB_GRACE_SECONDS, s.DEBUG)"
)


def test_database_outage_settings() -> None:
    defaults = _import_settings(GOOD_ENV, _PRINT_DATABASE_SETTINGS)
    assert defaults.stdout.split() == ["3", "2", "120", "False"], defaults.stderr
    tuned = _import_settings(
        {
            **GOOD_ENV,
            "DB_CONNECT_TIMEOUT_SECONDS": "5",
            "DB_RETRY_AFTER_SECONDS": "4",
            "READINESS_DB_GRACE_SECONDS": "30",
            "DJANGO_DEBUG": "true",
        },
        _PRINT_DATABASE_SETTINGS,
    )
    assert tuned.stdout.split() == ["5", "4", "30", "True"], tuned.stderr


def test_settings_reject_a_non_integer() -> None:
    result = _import_settings({**GOOD_ENV, "DB_RETRY_AFTER_SECONDS": "soon"})
    assert result.returncode != 0
    assert "DB_RETRY_AFTER_SECONDS must be an integer" in result.stderr
