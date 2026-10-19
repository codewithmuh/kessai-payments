"""Database outages: which errors become 503 + Retry-After, and when a pod goes unready."""

from __future__ import annotations

from typing import Any

import pytest
from django.db import DataError, IntegrityError, InterfaceError, InternalError, OperationalError
from django.test import RequestFactory
from rest_framework import exceptions

from core.database import DatabaseReadiness, unavailable_reason
from core.errors import (
    ConflictError,
    NotFoundError,
    UnprocessableError,
    bad_request,
    exception_handler,
    permission_denied,
    server_error,
)
from core.middleware import DatabaseUnavailableMiddleware


class _PsycopgError(Exception):
    """Stands in for psycopg's error, which carries the server's SQLSTATE."""

    def __init__(self, sqlstate: str | None) -> None:
        super().__init__("server message")
        self.sqlstate = sqlstate


def _django_error(cls: type[Exception], sqlstate: str | None) -> Exception:
    error = cls("wrapped")
    error.__cause__ = _PsycopgError(sqlstate)
    return error


@pytest.mark.parametrize(
    ("error", "reason"),
    [
        (InterfaceError("connection already closed"), "connection"),
        (OperationalError("connection refused"), "connection"),  # no SQLSTATE: never answered
        (_django_error(OperationalError, "08006"), "connection"),
        (_django_error(OperationalError, "57P01"), "shutdown"),
        (_django_error(OperationalError, "57P03"), "shutdown"),
        (_django_error(InternalError, "25006"), "read_only"),
        (_django_error(OperationalError, "53300"), "too_many_connections"),
        (_django_error(OperationalError, "57014"), "timeout"),
        (_django_error(OperationalError, "40P01"), None),  # deadlock: a bug, not an outage
        (InternalError("no sqlstate"), None),
        (IntegrityError("duplicate key"), None),
        (DataError("bad value"), None),
        (ValueError("not a database error"), None),
    ],
)
def test_unavailable_reason(error: Exception, reason: str | None) -> None:
    assert unavailable_reason(error) == reason


def test_readiness_grace_window() -> None:
    now = [0.0]
    readiness = DatabaseReadiness(grace_s=120, clock=lambda: now[0])
    assert readiness.record(answered=False).ready is False  # never answered: not ready
    assert readiness.record(answered=True).ready is True
    now[0] = 10.0
    verdict = readiness.record(answered=False)
    assert (verdict.ready, verdict.failing_for_s) == (True, 0.0)
    now[0] = 129.0
    assert readiness.record(answered=False).ready is True
    now[0] = 130.0
    assert readiness.record(answered=False).ready is False  # failing for the whole grace
    assert readiness.record(answered=True).ready is True  # one answer resets the streak


def _middleware() -> DatabaseUnavailableMiddleware:
    def get_response(request: Any) -> Any:
        raise AssertionError("not called")

    return DatabaseUnavailableMiddleware(get_response)


def test_outage_becomes_503_with_retry_after() -> None:
    request = RequestFactory().post("/v1/payments")
    response = _middleware().process_exception(request, _django_error(OperationalError, "57P01"))
    assert response is not None
    assert response.status_code == 503
    assert response["Retry-After"] == "2"
    assert b"database_unavailable" in response.content


def test_other_errors_are_left_to_django() -> None:
    request = RequestFactory().post("/v1/payments")
    assert _middleware().process_exception(request, IntegrityError("duplicate key")) is None


@pytest.mark.parametrize(
    ("error", "status", "code"),
    [
        (NotFoundError(), 404, "not_found"),
        (ConflictError("Already refunded."), 409, "conflict"),
        (UnprocessableError("Insufficient balance."), 422, "unprocessable"),
    ],
)
def test_domain_errors_have_one_json_shape(error: Exception, status: int, code: str) -> None:
    response = exception_handler(error, {})
    assert response is not None
    assert response.status_code == status
    assert response.data["error"]["code"] == code


def test_drf_errors_have_the_same_shape() -> None:
    invalid = exception_handler(exceptions.ValidationError({"amount": ["Required."]}), {})
    assert invalid is not None
    assert invalid.data["error"]["code"] == "validation_error"
    assert invalid.data["error"]["details"] == {"amount": ["Required."]}
    unauthenticated = exception_handler(exceptions.NotAuthenticated(), {})
    assert unauthenticated is not None
    assert unauthenticated.data["error"]["code"] == "not_authenticated"
    assert exception_handler(RuntimeError("bug"), {}) is None  # left to Django's handler500


def test_django_error_pages_are_json() -> None:
    request = RequestFactory().get("/")
    assert bad_request(request).status_code == 400
    assert permission_denied(request).status_code == 403
    assert server_error(request).status_code == 500
