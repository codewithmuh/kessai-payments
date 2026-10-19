"""Test settings: fake secrets, then the real settings module.

DATABASE_URL decides the database. Unset, tests run on in-memory SQLite (tests marked `postgres` are
skipped); CI points it at a PostgreSQL service so every test runs.
"""

import os

_FAKE = {
    "DJANGO_SECRET_KEY": "test-only-django-secret-key-not-used-anywhere-else",
    "DATABASE_URL": "sqlite://:memory:",
}
for _name, _value in _FAKE.items():
    os.environ.setdefault(_name, _value)

from config.settings import *  # noqa: E402, F403
