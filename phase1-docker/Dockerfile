# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: builder
# Install dependencies in isolation so the final image stays lean.
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# Install build tools (needed for some C-extension packages like asyncpg)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements first — Docker caches this layer.
# If requirements.txt hasn't changed, pip install is skipped on rebuild.
COPY requirements.txt .

RUN pip install --upgrade pip && \
    pip install --no-cache-dir --prefix=/install -r requirements.txt


# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: final image
# Copy only what's needed — no gcc, no build tools, no cache.
# ─────────────────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS final

# Runtime system deps only
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# ── Non-root user ─────────────────────────────────────────────────────────────
# Running as root inside a container is a security risk.
# K8s PodSecurityPolicy / SecurityContext will enforce this anyway in prod.
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --shell /bin/bash --create-home appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY --chown=appuser:appgroup ./app ./app

# Switch to non-root
USER appuser

EXPOSE 8000

# ── Health check ──────────────────────────────────────────────────────────────
# Docker itself will monitor this. docker-compose and K8s use their own probes,
# but this acts as a fallback and shows up in `docker ps` STATUS column.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# ── Entrypoint ────────────────────────────────────────────────────────────────
# --host 0.0.0.0 is required — default 127.0.0.1 won't be reachable from outside the container
# --workers 1 for dev; in prod use gunicorn or scale via K8s replicas instead
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
