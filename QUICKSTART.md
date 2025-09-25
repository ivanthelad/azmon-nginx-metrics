# 🚀 Quick Start Guide

Get your NGINX monitoring stack with blog API running in under 5 minutes.

## Prerequisites

- Docker and Docker Compose installed
- Azure subscription with a VM or resource to monitor
- Azure service principal or managed identity credentials

## 1. Setup (2 minutes)

```bash
# Clone the repository
git clone https://github.com/ivanthelad/azmon-nginx-metrics.git
cd azmon-nginx-metrics

# Configure Azure credentials
cp .env.example .env
```

Edit `.env` with your Azure details:
```bash
AZURE_SUBSCRIPTION_ID=your-subscription-id
AZURE_RESOURCE_GROUP=your-resource-group
AZURE_RESOURCE_NAME=your-vm-name
AZURE_CLIENT_ID=your-client-id
AZURE_CLIENT_SECRET=your-client-secret
AZURE_TENANT_ID=your-tenant-id
```

## 2. Launch (1 minute)

Choose your deployment method:

### Option A: Local Development (Build from source)
```bash
# Start all services including blog-api
docker-compose up -d

# Verify services are running
docker-compose ps
```

### Option B: Production (Pre-built images from GitHub Container Registry)
```bash
# Use pre-built images for faster startup
docker-compose -f docker-compose.ghcr.yml up -d

# Verify services are running
docker-compose -f docker-compose.ghcr.yml ps
```

Expected output:
```
NAME                        COMMAND                  SERVICE             STATUS              PORTS
blog-api                    "python app.py"          blog-api            running
metrics-collector           "python azure_monitor…"  metrics-collector   running
nginx-prometheus-exporter   "python nginx_promet…"   nginx-exporter      running             0.0.0.0:9113->9113/tcp
nginx-server                "/docker-entrypoint.…"   nginx               running             0.0.0.0:80->80/tcp
otel-exporter              "python app.py"          otel-exporter       running             0.0.0.0:8000->8000/tcp (optional)
```

## 3. Test (1 minute)

```bash
# Test NGINX
curl http://localhost/health
# Expected: "healthy"

# Test Blog API through NGINX proxy
curl http://localhost/blog/health
# Expected: {"status": "healthy"}

# Test Prometheus metrics
curl -s http://localhost:9113/metrics | grep nginx_connections_active
# Expected: nginx_connections_active_total 1.0

# Test Azure Monitor connection
docker-compose exec metrics-collector python azure_monitor_sender.py --health-check
# Expected: "✅ Healthy"
```

## 4. Explore (1 minute)

**Web Interface:**
Open http://localhost in your browser for:
- Live metrics display
- Load testing buttons
- Real-time statistics

**Blog API Endpoints:**
- `GET http://localhost/blog/health` - Health check
- `GET http://localhost/blog/posts` - List blog posts
- `POST http://localhost/blog/posts` - Create new post

**Prometheus Metrics:**
Visit http://localhost:9113/metrics to see all 50+ available metrics

**Status Endpoints:**
- http://localhost/nginx_status - Basic NGINX metrics
- http://localhost/status_json - JSON status information

## 5. Generate Test Data

```bash
# Generate web traffic for immediate metrics
for i in {1..20}; do curl http://localhost/api/v1/fast; done
for i in {1..5}; do curl http://localhost/api/v1/slow; done
for i in {1..10}; do curl http://localhost/api/v1/error; done

# Test blog API endpoints
curl -X POST http://localhost/blog/posts \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Post","content":"Hello World"}'

curl http://localhost/blog/posts

# Check metrics again
curl -s http://localhost:9113/metrics | grep nginx_server_requests_total
```

## 6. View in Azure Portal

1. Go to Azure Portal → Your VM resource
2. Navigate to **Monitoring** → **Metrics**
3. Select namespace: **"Custom/NGINX"**
4. Choose metrics like:
   - `nginx_connections_active_total`
   - `nginx_http_requests_total`
   - `nginx_server_requests_total`

## 7. Cloud Deployment

### VM Deployment with Cloud-Init
Deploy to Azure VM with automatic setup:

```bash
# Deploy VM with cloud-init (includes blog-api)
cd vm-setup
./0-deploy-vm.sh my-resource-group northeurope ~/.ssh/id_rsa.pub my-nginx-vm
```

The cloud-init configuration automatically:
- Installs Docker and dependencies
- Pulls images from GitHub Container Registry
- Starts all services including blog-api
- Configures Azure Monitor integration
- Sets up automatic startup on boot

## Available Docker Compose Files

- `docker-compose.yml` - Local development (builds from source)
- `docker-compose.ghcr.yml` - GitHub Container Registry images
- `docker-compose.acr.yml` - Azure Container Registry images
- `docker-compose.simple.yml` - Minimal setup (nginx + blog-api only)

## Container Images

All images are automatically built and published via GitHub Actions:

**GitHub Container Registry:**
- `ghcr.io/ivanthelad/azmon-nginx-metrics/nginx:latest`
- `ghcr.io/ivanthelad/azmon-nginx-metrics/nginx-exporter:latest`
- `ghcr.io/ivanthelad/azmon-nginx-metrics/metrics-collector:latest`
- `ghcr.io/ivanthelad/azmon-nginx-metrics/blog-api:latest`
- `ghcr.io/ivanthelad/azmon-nginx-metrics/otel-exporter:latest`

## Troubleshooting

**Services not starting?**
```bash
docker-compose logs nginx
docker-compose logs nginx-exporter
docker-compose logs metrics-collector
docker-compose logs blog-api
```

**No metrics in Azure?**
```bash
# Check Azure connectivity
docker-compose exec metrics-collector python azure_monitor_sender.py --config-check

# Test sending metrics
docker-compose exec metrics-collector python azure_monitor_sender.py --send-test
```

**Blog API not responding?**
```bash
# Check blog-api logs
docker-compose logs blog-api

# Test direct connection (if using container networking)
docker-compose exec nginx curl http://blog-api:5000/health
```

**Port conflicts?**
```bash
# Check what's using ports
sudo lsof -i :80   # NGINX
sudo lsof -i :9113 # Prometheus exporter
sudo lsof -i :5000 # Blog API (internal)
sudo lsof -i :8000 # OpenTelemetry exporter (optional)

# Use different external ports in docker-compose.yml if needed
```

**Image pull failures?**
```bash
# For GHCR images, ensure they're public or login if private
docker login ghcr.io

# Check if images exist
docker pull ghcr.io/ivanthelad/azmon-nginx-metrics/nginx:latest
```

## What's Next?

- **Set up alerts** in Azure Monitor for key metrics
- **Create dashboards** using the Custom/NGINX metrics namespace
- **Develop with the Blog API** for your application backend
- **Scale the setup** with container orchestration
- **Deploy to production** using Azure Container Instances or AKS
- **Explore advanced features** in the full [README.md](README.md)

## Architecture Overview

```
Internet → NGINX (Port 80) → Blog API (Port 5000)
    ↓
NGINX Exporter (Port 9113) → Prometheus Metrics
    ↓
Metrics Collector → Azure Monitor Custom Metrics
    ↓
Optional: OpenTelemetry Exporter (Port 8000)
```

---

🎉 **You're now monitoring NGINX with 50+ metrics flowing to Azure Monitor, plus a functional blog API backend!**