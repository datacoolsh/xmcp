# Build stage: install dependencies using uv
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim AS builder

WORKDIR /app

# Copy dependency files and install (without project itself)
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project --no-dev

# Runtime stage
FROM python:3.12-slim-bookworm

WORKDIR /app

# Copy the installed virtualenv from builder
COPY --from=builder /app/.venv /app/.venv

# Copy application code
COPY server.py ./

# Ensure the venv is on PATH
ENV PATH="/app/.venv/bin:$PATH"

# Expose MCP HTTP port
EXPOSE 8009

# NOTE: OAuth1 browser flow is not available in containers.
# You must provide X_OAUTH_ACCESS_TOKEN and X_OAUTH_ACCESS_TOKEN_SECRET
# via environment variables (or .env file mounted at runtime).

CMD ["python", "server.py"]
