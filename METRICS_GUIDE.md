# Comprehensive NGINX Metrics Guide

This document describes all the metrics available from the NGINX monitoring stack.

## Available Metrics Endpoints

### 1. NGINX Server Endpoints
- **Main Site**: http://localhost/
- **Health Check**: http://localhost/health
- **Basic Metrics**: http://localhost/nginx_status
- **VTS HTML Dashboard**: http://localhost/vts_status
- **VTS JSON Metrics**: http://localhost/vts_json

### 2. Prometheus Exporter
- **Prometheus Metrics**: http://localhost:9113/metrics
- **Exporter Health**: http://localhost:9113/health

### 3. Test Endpoints (for generating diverse metrics)
- **Fast API**: http://localhost/api/v1/fast
- **Slow API**: http://localhost/api/v1/slow
- **Error API**: http://localhost/api/v1/error
- **Not Found**: http://localhost/api/v1/not_found
- **Large Response**: http://localhost/large
- **Rate Limited**: http://localhost/login (1 req/sec limit)

## Comprehensive Metrics Collection

### Basic NGINX Metrics (stub_status)
```
nginx_connections_active_total - Active connections
nginx_connections_accepted_total - Total accepted connections
nginx_connections_handled_total - Total handled connections
nginx_http_requests_total - Total HTTP requests
nginx_connections_reading - Connections reading requests
nginx_connections_writing - Connections writing responses
nginx_connections_waiting - Connections waiting (keep-alive)
```

### Enhanced VTS Metrics

#### Server Zone Metrics
```
nginx_server_requests_total{server_name, code} - Requests by server and status code
nginx_server_bytes_sent_total{server_name} - Bytes sent by server
nginx_server_bytes_received_total{server_name} - Bytes received by server
nginx_server_request_duration_seconds{server_name} - Request duration histogram
```

#### Upstream Metrics (for load balancing)
```
nginx_upstream_requests_total{upstream, server, code} - Upstream requests
nginx_upstream_response_duration_seconds{upstream, server} - Upstream response time
nginx_upstream_bytes_sent_total{upstream, server} - Bytes sent to upstream
nginx_upstream_bytes_received_total{upstream, server} - Bytes received from upstream
```

#### Location/URI Metrics
```
nginx_location_requests_total{server_name, location, code} - Requests by location
nginx_location_bytes_sent_total{server_name, location} - Bytes sent by location
nginx_location_response_duration_seconds{server_name, location} - Location response time
```

#### Cache Metrics
```
nginx_cache_status_total{server_name, status} - Cache hit/miss/bypass statistics
```

#### Application Performance Metrics
```
nginx_request_size_bytes{server_name} - Request size distribution
nginx_response_size_bytes{server_name} - Response size distribution
```

#### Exporter Health Metrics
```
nginx_exporter_scrapes_total{result} - Total scrapes (success/failed/error)
nginx_exporter_scrape_duration_seconds - Scrape duration histogram
```

## Rate Limiting and Security Metrics

The NGINX configuration includes multiple rate limiting zones:
- **login**: 1 request/second (for authentication endpoints)
- **api**: 10 requests/second (for API endpoints)
- **general**: 100 requests/second (for general traffic)

These generate metrics about:
- Rate limit violations
- Connection limits
- Request patterns by endpoint

## VTS Module Features

The VTS (Virtual Host Traffic Status) module provides:

1. **Real-time HTML Dashboard** at `/vts_status`
2. **JSON API** at `/vts_json` for programmatic access
3. **Detailed Breakdowns** by:
   - Server blocks
   - Upstream groups
   - Location patterns
   - Response codes
   - Geographic regions (if GeoIP enabled)

## Testing the Metrics

### Generate Load for Testing
```bash
# Generate fast requests
for i in {1..100}; do curl http://localhost/api/v1/fast; done

# Generate slow requests
for i in {1..10}; do curl http://localhost/api/v1/slow & done; wait

# Generate error responses
for i in {1..50}; do curl http://localhost/api/v1/error; done

# Test rate limiting
for i in {1..20}; do curl http://localhost/login; done
```

### Monitor Metrics in Real-time
```bash
# Watch Prometheus metrics
watch curl -s http://localhost:9113/metrics

# View VTS dashboard
open http://localhost/vts_status

# Check basic status
watch curl -s http://localhost/nginx_status
```

## Azure Monitor Integration

All metrics are automatically sent to Azure Monitor Custom Metrics under the namespace `Custom/NGINX`. You can view them in the Azure Portal under:

1. Your VM resource → Monitoring → Metrics
2. Select namespace: "Custom/NGINX"
3. Available metrics include all the Prometheus metrics listed above

## Alerting Recommendations

Set up Azure Monitor alerts for:

### Performance Alerts
- High response times: `nginx_server_request_duration_seconds > 2s`
- High error rates: `nginx_server_requests_total{code="5xx"} / nginx_server_requests_total > 0.05`
- Connection saturation: `nginx_connections_active_total > 800`

### Availability Alerts
- Service down: `nginx_exporter_scrapes_total{result="failed"}` increasing
- High 4xx rates: `nginx_server_requests_total{code="4xx"}` spike

### Capacity Alerts
- High request rate: `rate(nginx_http_requests_total[5m]) > 1000`
- High bandwidth: `rate(nginx_server_bytes_sent_total[5m]) > 100MB`

## Log Analysis

NGINX logs are available in multiple formats:
- **Standard format** in `/var/log/nginx/access.log`
- **JSON format** in `/var/log/nginx/access.json`

The JSON logs include timing information for correlation with metrics:
```json
{
  "time_local": "2024-01-01T12:00:00",
  "request": "GET /api/v1/fast HTTP/1.1",
  "status": "200",
  "request_time": "0.001",
  "upstream_response_time": "0.001"
}
```

## Troubleshooting

### Check Service Health
```bash
docker-compose ps
docker-compose logs nginx
docker-compose logs nginx-exporter
docker-compose logs metrics-collector
```

### Verify Metrics Collection
```bash
# Test NGINX endpoints
curl http://localhost/health
curl http://localhost/nginx_status

# Test Prometheus exporter
curl http://localhost:9113/health
curl http://localhost:9113/metrics

# Test Azure Monitor connection
docker-compose exec metrics-collector python azure_monitor_sender.py --health-check
```

### Debug VTS Module
```bash
# Check if VTS module is loaded
docker-compose exec nginx nginx -V 2>&1 | grep vts

# Test VTS endpoints
curl http://localhost/vts_json | jq .
```