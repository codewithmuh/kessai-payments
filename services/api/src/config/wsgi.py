"""WSGI entry point for gunicorn (`gunicorn --config python:config.gunicorn config.wsgi`)."""

import logging
import os

from django.conf import settings
from django.core.wsgi import get_wsgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

application = get_wsgi_application()

logging.getLogger("kessai").info("worker started", extra={"version": settings.APP_VERSION})
