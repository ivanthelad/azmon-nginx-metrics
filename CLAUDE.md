# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Architecture

This is a Docker-based NGINX monitoring stack that collects metrics and sends them to Azure Monitor. The architecture consists of 4 main components:

1. **nginx**: Web server with stub_status module for basic metrics and custom test endpoints
2. **nginx-exporter**: Custom Python Prometheus exporter that scrapes NGINX metrics and exposes them in Prometheus format
3. **metrics-collector**: Python service that scrapes Prometheus metrics and sends them to Azure Monitor Custom Metrics
4. **otel-exporter**: Optional OpenTelemetry-compatible service (disabled by default, use `--profile otel`)

## Key Docker Commands

Since all services are containerized, always use Docker commands for this project:

```bash
# Build and start all services
docker-compose up -d

# Build specific service after code changes
docker-compose build nginx-exporter
docker-compose build metrics-collector

# View logs for debugging
docker-compose logs nginx-exporter
docker-compose logs metrics-collector

# Stop all services
docker-compose down

# Test health of individual services
docker-compose exec metrics-collector python azure_monitor_sender.py --health-check

# Restart specific service
docker-compose restart nginx-exporter
```

## Development Workflow

When making changes to Python services:
1. Edit code in respective directories (`nginx-exporter/`, `azmonitor-metrics/`)
2. Rebuild the specific service: `docker-compose build <service-name>`
3. Restart the service: `docker-compose restart <service-name>`
4. Check logs: `docker-compose logs <service-name>`

## Configuration

- **Environment variables**: Defined in `.env` file (copy from `.env.example`)
- **Azure credentials**: Required in `.env` for metrics-collector service
- **NGINX config**: Located in `nginx/nginx.conf` and `nginx/default.conf`
- **Service endpoints**:
  - NGINX: http://localhost (port 80)
  - Prometheus metrics: http://localhost:9113/metrics
  - OpenTelemetry (optional): http://localhost:8000

## Important Implementation Details

### NGINX Metrics Collection
The system was originally designed for VTS (Virtual Host Traffic Status) module but has been converted to use standard nginx stub_status module due to Alpine Linux package availability. The nginx-exporter now scrapes:
- `/nginx_status` for basic stub_status metrics
- `/status_json` for basic JSON status information

### Custom Prometheus Exporter
The `nginx_prometheus_exporter.py` is a custom implementation that:
- Runs a background scraping loop every 15 seconds
- Exposes metrics via Flask app on port 9113
- Uses prometheus_client library for metric types (Counter, Gauge, Histogram)
- Handles connection errors gracefully and continues scraping

### Azure Monitor Integration
The `azure_monitor_sender.py`:
- Uses Azure Identity SDK for authentication
- Sends metrics to Azure Monitor Custom Metrics API
- Supports both service principal and managed identity authentication
- Includes retry logic and error handling

## Testing Endpoints

NGINX includes built-in test endpoints for generating metrics:
- `/api/v1/fast` - Fast responses
- `/api/v1/slow` - Simulated slow responses
- `/api/v1/error` - 500 errors
- `/api/v1/not_found` - 404 errors
- `/health` - Health check endpoint

## Environment Variables

Key environment variables (set in `.env`):
- `AZURE_*` - Azure credentials for metrics-collector
- `SCRAPE_INTERVAL` - How often to send metrics to Azure (default: 60s)
- `NGINX_STATUS_URL` - URL for nginx-exporter to scrape basic metrics
- `NGINX_JSON_URL` - URL for nginx-exporter to scrape JSON status

## Common Issues

1. **VTS module errors**: The system no longer uses VTS module - it was removed due to Alpine Linux compatibility
2. **Container connectivity**: Services communicate via Docker network using container names (e.g., `http://nginx/nginx_status`)
3. **Azure authentication**: Ensure Azure credentials are correctly set in `.env` file
4. **Port conflicts**: Default ports are 80 (nginx) and 9113 (exporter)

## Directory Structure

- `nginx/` - NGINX configuration and Dockerfile
- `nginx-exporter/` - Custom Prometheus exporter (Python/Flask)
- `azmonitor-metrics/` - Azure Monitor integration (Python)
- `ingestor/` - Optional OpenTelemetry exporter
- `logs/` - Persistent log storage (mounted volumes)

## GitHub Repository Constraints

**CRITICAL SAFETY CONSTRAINTS** - Claude must follow these rules at all times:

1. **Repository Restriction**: Only work with this specific repository: https://github.com/ivanthelad/azmon-nginx-metrics
   - NEVER perform operations on any other GitHub repository
   - Always verify repository URL before any GitHub operations
   - If asked to work with a different repository, refuse and remind user of this constraint

2. **No Destructive GitHub Operations**: NEVER use commands that delete or destroy GitHub repositories:
   - NEVER use `gh repo delete`
   - NEVER use `git push --force` on main/master branch
   - NEVER delete branches without explicit user confirmation
   - NEVER perform operations that could result in data loss

3. **Authentication Verification**: Before any push operations:
   - Verify git authentication status
   - Confirm repository URL matches the allowed repository
   - Ask user to confirm if authentication setup is needed

4. **Safe Operations Only**: Only perform these GitHub operations:
   - `git push` (normal pushes)
   - `git pull`
   - `git clone` (only for the specified repository)
   - `gh pr create` (only for the specified repository)
   - `gh issue create` (only for the specified repository)

These constraints protect against accidental operations on wrong repositories or destructive actions.