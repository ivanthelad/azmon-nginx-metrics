# NGINX Azure Monitor Stack for Autoscaling

Docker-based monitoring solution that enables Azure VMSS autoscaling based on NGINX application metrics.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│                 │    │                  │    │                 │    │                 │
│     NGINX       │───▶│ nginx-exporter   │───▶│ metrics-        │───▶│ Azure Monitor   │
│                 │    │                  │    │ collector       │    │ Custom Metrics  │
│ :80/nginx_status│    │ :9113/metrics    │    │                 │    │                 │
│                 │    │                  │    │ • Scrapes :9113 │    │ Custom/NGINX    │
│ • HTTP requests │    │ • Converts to    │    │ • Transforms    │    │ namespace       │
│ • Active conns  │    │   Prometheus     │    │ • Sends via API │    │                 │
│ • Status codes  │    │ • Calculates RPS │    │ • Managed ID    │    │ • Autoscaling   │
└─────────────────┘    └──────────────────┘    └─────────────────┘    └─────────────────┘
```

## Problem

Azure VMSS can only autoscale on Azure Monitor metrics, not Prometheus metrics or Log Analytics queries.

## Solution

Bridge NGINX metrics to Azure Monitor Custom Metrics to enable intelligent autoscaling based on `nginx_requests_per_second`.

## Deployment Scripts

Execute in order. Each script displays the exact command for the next step at completion - copy and paste to continue:

### Step 0: Create baseline VM
```bash
./vm-setup/0-deploy-vm.sh [resource-group] [location] [ssh-key-path] [vm-name]
```
Creates Ubuntu VM with NGINX monitoring stack via cloud-init.

### Step 1: Capture custom image
```bash
./vm-setup/1-create-image-gallery.sh [gallery-rg] [location] [gallery-name] [source-vm-rg] [source-vm-name]
```
Creates Shared Image Gallery and captures VM as reusable custom image.

### Step 2.1: Deploy single VM (optional)
```bash
./vm-setup/2.1-deploy-vm-from-image.sh [vm-rg] [location] [ssh-key-path] [vm-name] [image-gallery-rg] [gallery-name]
```
Deploys single production VM from custom image.

### Step 2.2: Deploy VMSS with autoscaling (recommended)
```bash
./vm-setup/2.2-deploy-vmss-from-image.sh [vmss-rg] [location] [ssh-key-path] [vmss-name] [instance-count] [image-gallery-rg] [gallery-name]
```
Deploys VMSS with load balancer and autoscaling rules:
- CPU-based: Scale at 70%/30%
- Custom metrics: Scale based on `nginx_requests_per_second > 200`

## Complete Workflow

```bash
# Create baseline
./vm-setup/0-deploy-vm.sh rg-base northeurope ~/.ssh/id_rsa.pub vm-base

# Capture image
./vm-setup/1-create-image-gallery.sh rg-gallery northeurope nginx_gallery rg-base vm-base

# Deploy VMSS
./vm-setup/2.2-deploy-vmss-from-image.sh rg-prod northeurope ~/.ssh/id_rsa.pub vmss-prod 2 rg-gallery nginx_gallery
```

## Add Autoscaling to Existing VMSS

```bash
./create-autoscale-rules.sh
```

Result: VMSS scales based on actual HTTP traffic instead of just CPU utilization.

## Docker Images

Docker images are automatically built and pushed to GitHub Container Registry via GitHub Actions:

- `ghcr.io/ivanthelad/azmon-nginx-metrics/nginx` - NGINX with monitoring endpoints
- `ghcr.io/ivanthelad/azmon-nginx-metrics/nginx-exporter` - Prometheus metrics exporter
- `ghcr.io/ivanthelad/azmon-nginx-metrics/metrics-collector` - Azure Monitor integration
- `ghcr.io/ivanthelad/azmon-nginx-metrics/otel-exporter` - OpenTelemetry exporter (optional)
- `ghcr.io/ivanthelad/azmon-nginx-metrics/blog-api` - Sample API service

Images are built on every push to main/develop branches and tagged releases. Multi-architecture support (AMD64/ARM64).