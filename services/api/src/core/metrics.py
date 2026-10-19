"""Prometheus metrics: HTTP RED metrics from the runtime contract, plus database outages.

Business counters (payments, refunds, ledger, webhooks) are added next to the code that counts them.

Under gunicorn several worker processes serve /metrics, so prometheus_client runs in multiprocess
mode (PROMETHEUS_MULTIPROC_DIR, set in config/gunicorn.py) and the scrape sums every worker's
samples.
"""

from __future__ import annotations

import os

from prometheus_client import (
    CONTENT_TYPE_LATEST,
    REGISTRY,
    CollectorRegistry,
    Counter,
    Histogram,
    generate_latest,
    multiprocess,
)

# In multiprocess mode each process writes its samples to files in this directory. It must exist
# before the first metric is created, in every process that sees the variable (gunicorn's
# on_starting also empties it at startup).
if _multiproc_dir := os.environ.get("PROMETHEUS_MULTIPROC_DIR"):
    os.makedirs(_multiproc_dir, exist_ok=True)

HTTP_REQUESTS = Counter("http_requests_total", "HTTP requests.", ["method", "route", "status"])
HTTP_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency.",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1.0, 2.5, 5.0),
)

# Also counted in http_requests_total{status="503"}, which is what an availability SLI reads.
DATABASE_UNAVAILABLE = Counter(
    "kessai_database_unavailable_total",
    "Requests answered 503 database_unavailable because PostgreSQL could not serve them.",
    ["route", "reason"],
)


def render_latest() -> tuple[bytes, str]:
    """The exposition text for /metrics and its content type."""
    if "PROMETHEUS_MULTIPROC_DIR" in os.environ:
        registry = CollectorRegistry()
        multiprocess.MultiProcessCollector(registry)  # type: ignore[no-untyped-call]
        return generate_latest(registry), CONTENT_TYPE_LATEST
    return generate_latest(REGISTRY), CONTENT_TYPE_LATEST
