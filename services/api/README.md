# api

The Kessai service: Django 5.2 LTS + Django REST framework on PostgreSQL, Python 3.13. The design it builds
towards is in [docs/scope.md](../../docs/scope.md).

| Path | What it holds |
|---|---|
| `src/config/` | Settings from environment variables only (secrets have no defaults), URLs, gunicorn, WSGI |
| `src/core/` | Plumbing every app uses: probes and metrics middleware, JSON logs, the JSON error format, database-outage handling (503 + Retry-After), graceful shutdown |
| `tests/` | pytest + pytest-django. SQLite by default; set `DATABASE_URL` to PostgreSQL to run the `postgres`-marked tests too (CI does) |

Add each app with `uv run python manage.py startapp <name> src/<name>`, then add it to `INSTALLED_APPS`
(`src/config/settings.py`) and to `packages` in `pyproject.toml` (mypy).

One image runs every process; the API is the default command. Migrations run as a separate pre-deploy job
(`python manage.py migrate --noinput`), never at startup, because replicas would race.

```bash
uv sync
uv run pytest                                                     # SQLite
DATABASE_URL=postgres://kessai:kessai-local-only@localhost:5432/kessai uv run pytest   # PostgreSQL from `make up`
```
