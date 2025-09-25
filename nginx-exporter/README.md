# NGINX Prometheus Exporter

Custom Python exporter that converts NGINX metrics to Prometheus format.

## Purpose

Scrapes NGINX status endpoints and exposes metrics in Prometheus format at `:9113/metrics` for consumption by metrics-collector.

## Metrics Collection

- **Source**: NGINX `/nginx_status` (stub_status) and `/status_json` endpoints
- **Scrape interval**: 15 seconds (configurable)
- **Output format**: Prometheus metrics format

## Exposed Metrics

- `nginx_connections_active_total` - Active connections
- `nginx_connections_reading_total` - Connections reading requests
- `nginx_connections_writing_total` - Connections writing responses
- `nginx_connections_waiting_total` - Idle connections waiting
- `nginx_server_requests_total` - Total requests handled
- `nginx_connections_accepted_total` - Total connections accepted
- `nginx_connections_handled_total` - Total connections handled

## Endpoints

- `GET /metrics` - Prometheus metrics output
- `GET /health` - Health check endpoint

## Configuration

Environment variables:
- `NGINX_STATUS_URL` - NGINX stub_status endpoint (default: `http://nginx/nginx_status`)
- `NGINX_JSON_URL` - NGINX JSON status endpoint (default: `http://nginx/status_json`)
- `SCRAPE_INTERVAL` - Collection frequency in seconds (default: `15`)
- `EXPORTER_PORT` - Server port (default: `9113`)

## Operation

Runs Flask server on port 9113 with background thread that scrapes NGINX metrics every 15 seconds and maintains Prometheus metrics registry.