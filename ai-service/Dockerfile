FROM python:3.11-slim

WORKDIR /app

# Native build deps are needed for packages like llama-cpp-python.
RUN apt-get update && apt-get install -y --no-install-recommends \
	gcc \
	g++ \
	make \
	cmake \
	&& rm -rf /var/lib/apt/lists/*

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir torch==2.2.2 --index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY api ./api

# Create models directory if not exists
RUN mkdir -p /app/models

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Expose port
EXPOSE 8001

# Run application
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8001"]
