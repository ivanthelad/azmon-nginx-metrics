# 🚀 Quick Start Guide

Deploy NGINX monitoring stack to Azure VM with managed identity.

## Prerequisites

- Azure subscription
- Azure VM with system-assigned managed identity enabled
- VM has **Monitoring Contributor** role for custom metrics

## 1. Deploy VM with Cloud-Init

```bash
# Deploy VM with automatic setup
./vm-setup/0-deploy-vm.sh my-resource-group northeurope ~/.ssh/id_rsa.pub my-nginx-vm
```

This automatically:
- Creates Ubuntu VM with Docker
- Enables system-assigned managed identity
- Pulls and starts all containers from GHCR
- Configures Azure Monitor integration via IMDS

## 2. Test the Deployment

```bash
# SSH to the VM (replace with your VM's public IP)
ssh azureuser@<vm-public-ip>

# Check services are running
docker-compose ps

# Test endpoints
curl http://localhost/health
curl http://localhost/blog/health
curl -s http://localhost:9113/metrics | grep nginx_connections_active

# Test Azure Monitor connection
docker-compose exec metrics-collector python azure_monitor_sender.py --health-check
```

## 3. View Metrics in Azure Portal

1. Go to Azure Portal → Your VM resource
2. Navigate to **Monitoring** → **Metrics**
3. Select **Custom** namespace → **Custom/NGINX**
4. Choose metrics: `nginx_connections_active_total`, `nginx_http_requests_total`

## 4. Scale to VMSS (Optional)

```bash
# Create custom image from VM
./vm-setup/1-create-image-gallery.sh gallery-rg northeurope nginx_gallery vm-rg my-nginx-vm

# Deploy VMSS with autoscaling
./vm-setup/2.2-deploy-vmss-from-image.sh vmss-rg northeurope ~/.ssh/id_rsa.pub nginx-vmss 2 gallery-rg nginx_gallery
```

## How It Works

- **NGINX** serves traffic and exposes `/nginx_status` endpoint
- **nginx-exporter** scrapes NGINX metrics, converts to Prometheus format
- **metrics-collector** scrapes Prometheus metrics, sends to Azure Monitor via managed identity
- **blog-api** provides test endpoints for realistic traffic patterns
- **IMDS** auto-discovers VM/VMSS configuration for Azure Monitor integration

## Container Images

All images published to GitHub Container Registry:
- `ghcr.io/ivanthelad/azmon-nginx-metrics/nginx:latest`
- `ghcr.io/ivanthelad/azmon-nginx-metrics/nginx-exporter:latest`
- `ghcr.io/ivanthelad/azmon-nginx-metrics/metrics-collector:latest`
- `ghcr.io/ivanthelad/azmon-nginx-metrics/blog-api:latest`