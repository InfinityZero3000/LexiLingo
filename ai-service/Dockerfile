FROM python:3.11.18-slim-bookworm@sha256:a83ba18aef0f865b1a4a611c2cf460fe446f2795673bbb9fe43be570439e3b39

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Native build deps are needed for packages like llama-cpp-python.
RUN apt-get update && apt-get install -y --no-install-recommends \
	gcc \
	g++ \
	make \
	cmake \
	&& rm -rf /var/lib/apt/lists/*

# Install dependencies
COPY requirements.txt constraints-ai.txt ./
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -c constraints-ai.txt -r requirements.txt \
      --extra-index-url https://download.pytorch.org/whl/cpu

# Copy application code
COPY api ./api
COPY service ./service

# The L2 external-knowledge corpus. DocumentIntelligenceService reads
# data/external_docs at startup and silently indexes nothing when the directory
# is absent, so leaving it out of the image disabled L2's local arm in
# production while the code kept reporting success.
COPY data/external_docs ./data/external_docs

# Fail the image build if direct ETL runtime imports are missing.
RUN python -c "import defusedxml, typer; from api.services.content_etl.cli import app"

# Create models directory if not exists
RUN mkdir -p /app/models

# Create non-root user
# /data/content-etl is a named volume; Docker seeds an empty volume's ownership
# from this directory, so without it the ETL cannot write as appuser.
RUN useradd -m -u 1000 appuser \
    && mkdir -p /data/content-etl \
    && chown -R appuser:appuser /app /data/content-etl
USER appuser

# Expose port
EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=5 \
  CMD python -c "import urllib.request; response = urllib.request.urlopen('http://127.0.0.1:8001/health', timeout=3); raise SystemExit(0 if response.status == 200 else 1)"

# Run application
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8001"]
