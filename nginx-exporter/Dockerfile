FROM python:3.11-alpine

WORKDIR /app

# Install system dependencies
RUN apk add --no-cache \
    curl \
    bash \
    gcc \
    musl-dev \
    linux-headers

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY *.py ./

# Create non-root user
RUN adduser -D -s /bin/bash exporter && chown -R exporter:exporter /app
USER exporter

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9113/metrics || exit 1

# Expose Prometheus metrics port
EXPOSE 9113

# Environment variables
ENV NGINX_STATUS_URL=http://nginx/nginx_status
ENV NGINX_JSON_URL=http://nginx/status_json
ENV EXPORTER_PORT=9113
ENV SCRAPE_INTERVAL=15

CMD ["python", "nginx_prometheus_exporter.py"]