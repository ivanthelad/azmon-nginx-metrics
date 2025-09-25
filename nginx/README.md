# NGINX Web Server

NGINX configured for metrics collection and proxy functionality.

## Configuration

- **Port 80** - Main HTTP server
- **stub_status module** enabled for basic metrics at `/nginx_status`
- **JSON status endpoint** at `/status_json`
- **Enhanced logging** with request timings and upstream metrics
- **Security restrictions** - Status endpoints restricted to private networks

## Status Endpoints

### `/nginx_status`
Basic stub_status metrics:
```
Active connections: 1
server accepts handled requests
 7 7 7
Reading: 0 Writing: 1 Waiting: 0
```

### `/status_json`
JSON status information with server details and basic metrics.

## Proxy Configuration

Proxies `/blog/*` requests to `blog-api:5000` backend service.

## Test Endpoints

- `/health` - Health check
- `/api/v1/fast` - Fast response (50ms)
- `/api/v1/slow` - Slow response (2s)
- `/api/v1/error` - Returns 500 error
- `/api/v1/not_found` - Returns 404 error

## Logging

- **Access logs** - `/var/log/nginx/access.log` with enhanced format
- **Error logs** - `/var/log/nginx/error.log`
- **JSON logs** - Structured logging support for log aggregation

## Security

- Status endpoints restricted to:
  - localhost (127.0.0.1, ::1)
  - Private networks (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)