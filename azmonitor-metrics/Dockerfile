FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY *.py ./

# Create non-root user
RUN useradd --create-home --shell /bin/bash app && chown -R app:app /app
USER app

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python azure_monitor_sender.py --health-check || exit 1

# Default environment variables
ENV PROMETHEUS_URL=http://prometheus-exporter:9113/metrics
ENV SCRAPE_INTERVAL=15
ENV AZURE_REGION=northeurope

CMD python nginx_metrics_monitor.py --prometheus-url "$PROMETHEUS_URL" --interval "$SCRAPE_INTERVAL"