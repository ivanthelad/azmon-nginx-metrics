# Azure Shared Image Gallery Guide

## Script Execution Order

### Step 0: Create baseline VM
```bash
./0-deploy-vm.sh [resource-group] [location] [ssh-key-path] [vm-name]
```
- Deploys Ubuntu VM with cloud-init
- Installs Docker and NGINX monitoring stack
- Use for development/testing or as source for image capture

### Step 1: Capture custom image
```bash
./1-create-image-gallery.sh [gallery-rg] [location] [gallery-name] [source-vm-rg] [source-vm-name]
```
- Creates Shared Image Gallery
- Captures VM as custom image
- Source VM becomes unusable (generalized)

### Step 2.1: Deploy single VM from image
```bash
./2.1-deploy-vm-from-image.sh [vm-rg] [location] [ssh-key-path] [vm-name] [image-gallery-rg] [gallery-name]
```
- Deploys single production VM from custom image
- 2-3 minute deployment vs 10+ minutes with cloud-init

### Step 2.2: Deploy VMSS with autoscaling
```bash
./2.2-deploy-vmss-from-image.sh [vmss-rg] [location] [ssh-key-path] [vmss-name] [instance-count] [image-gallery-rg] [gallery-name]
```
- Deploys VMSS with load balancer
- Configures CPU and custom metrics autoscaling
- Scales based on `nginx_requests_per_second`

## Complete Workflow

```bash
# 1. Create baseline
./0-deploy-vm.sh rg-base northeurope ~/.ssh/id_rsa.pub vm-base

# 2. Capture image
./1-create-image-gallery.sh rg-gallery northeurope nginx_gallery rg-base vm-base

# 3. Deploy production VMSS
./2.2-deploy-vmss-from-image.sh rg-prod northeurope ~/.ssh/id_rsa.pub vmss-prod 2 rg-gallery nginx_gallery
```