from __future__ import annotations

from collections.abc import Iterator

import pytest
from django.conf import settings
from django.db import connection

from core import lifecycle, middleware
from core.database import DatabaseReadiness


@pytest.fixture(autouse=True)
def _fresh_process_state(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """Each test starts like a new process: not shutting down, database never checked."""
    monkeypatch.setattr(
        middleware,
        "database_readiness",
        DatabaseReadiness(grace_s=settings.READINESS_DB_GRACE_SECONDS),
    )
    yield
    lifecycle.reset()


def pytest_collection_modifyitems(config: pytest.Config, items: list[pytest.Item]) -> None:
    """Skip `postgres` tests on SQLite; CI sets DATABASE_URL to PostgreSQL so they run there."""
    if connection.vendor == "postgresql":
        return
    skip = pytest.mark.skip(reason="needs PostgreSQL (set DATABASE_URL)")
    for item in items:
        if "postgres" in item.keywords:
            item.add_marker(skip)
