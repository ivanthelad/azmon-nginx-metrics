# Azure VM/VMSS Deployment Scripts

This directory contains deployment scripts for setting up the NGINX Azure Monitor Stack on Azure infrastructure. The scripts follow a sequential deployment process to create reusable custom images and deploy them at scale.

## 📋 Deployment Overview

The deployment process follows this sequence:

1. **Step 0**: Deploy initial VM with cloud-init (development/testing)
2. **Step 1**: Create Shared Image Gallery and capture custom image
3. **Step 2.1**: Deploy single VM from custom image (production-ready)
4. **Step 2.2**: Deploy VMSS from custom image with autoscaling (scalable production)

## 🚀 Scripts Description

### 0-deploy-vm.sh - Initial Development VM

**Purpose**: Deploy a fresh Ubuntu VM with cloud-init setup for development and testing.

**What it does**:
- Creates a new resource group with unique suffix
- Deploys Ubuntu 24.04 VM with Standard_B2s size
- Sets up networking (VNet, subnet, NSG, public IP)
- Configures managed identity with monitoring permissions
- Uses cloud-init to install Docker and clone the repository
- Sets up the NGINX monitoring stack automatically
- Enables JIT SSH access for secure management

**Use case**: Development, testing, or creating a baseline VM to capture as an image.

**Usage**:
```bash
./0-deploy-vm.sh [resource-group] [location] [ssh-key-path] [vm-name]

# Example:
./0-deploy-vm.sh rg-nginx-dev northeurope ~/.ssh/id_rsa.pub vm-nginx-dev
```

**Output**: A fully configured VM running the NGINX monitoring stack, ready for testing or image capture.

---

### 1-create-image-gallery.sh - Custom Image Creation

**Purpose**: Create a Shared Image Gallery and capture a custom image from an existing configured VM.

**What it does**:
- Creates a new resource group for the image gallery
- Sets up Azure Shared Image Gallery with proper configuration
- Creates image definition for "nginx-monitor-ubuntu-2404"
- Generalizes the source VM (sysprep equivalent for Linux)
- Captures the VM as a custom image (version 1.0.0)
- Makes the image available for reuse across deployments

**Prerequisites**:
- An existing VM with the NGINX monitoring stack configured (from step 0)
- VM must be in running state before generalization

**Usage**:
```bash
./1-create-image-gallery.sh [gallery-rg] [location] [gallery-name] [source-vm-rg] [source-vm-name]

# Example:
./1-create-image-gallery.sh rg-nginx-gallery northeurope nginx_monitor_gallery rg-nginx-dev vm-nginx-dev
```

**Output**:
- Shared Image Gallery with custom image
- Image definition: `nginx-monitor-ubuntu-2404:1.0.0`
- Source VM deallocated and generalized (no longer usable)

**⚠️ Important**: The source VM will be generalized and cannot be used after this process.

---

### 2.1-deploy-vm-from-image.sh - Production Single VM

**Purpose**: Deploy a production-ready single VM using the custom image for faster deployment.

**What it does**:
- Creates a new resource group for the production VM
- Deploys VM using the custom image (much faster than cloud-init)
- Sets up networking and security groups
- Configures managed identity with monitoring permissions
- Automatically starts the Docker Compose stack on boot
- Enables JIT SSH access for management

**Prerequisites**:
- Custom image available in Shared Image Gallery (from step 1)
- Image gallery resource group and name

**Usage**:
```bash
./2.1-deploy-vm-from-image.sh [vm-rg] [location] [ssh-key-path] [vm-name] [image-gallery-rg] [gallery-name] [image-def] [image-version]

# Example:
./2.1-deploy-vm-from-image.sh rg-nginx-prod northeurope ~/.ssh/id_rsa.pub vm-nginx-prod rg-nginx-gallery nginx_monitor_gallery
```

**Output**: A production-ready VM with the NGINX monitoring stack running and sending metrics to Azure Monitor.

---

### 2.2-deploy-vmss-from-image.sh - Scalable Production VMSS

**Purpose**: Deploy a production VMSS with load balancer and intelligent autoscaling using the custom image.

**What it does**:
- Creates a new resource group for the VMSS deployment
- Deploys VMSS (1-4 instances) using the custom image
- Sets up Azure Load Balancer with health probes
- Configures networking (VNet, subnet, NSG)
- Creates managed identity with monitoring permissions
- **Configures dual autoscaling rules**:
  - CPU-based: Scale at 70%/30% CPU utilization
  - **Custom metrics**: Scale based on `nginx_requests_per_second`
- Each instance automatically runs the Docker Compose stack
- Sends aggregated metrics to Azure Monitor Custom Metrics

**Prerequisites**:
- Custom image available in Shared Image Gallery (from step 1)
- Image gallery resource group and name

**Usage**:
```bash
./2.2-deploy-vmss-from-image.sh [vmss-rg] [location] [ssh-key-path] [vmss-name] [instance-count] [image-gallery-rg] [gallery-name] [image-def] [image-version]

# Example:
./2.2-deploy-vmss-from-image.sh rg-nginx-vmss northeurope ~/.ssh/id_rsa.pub vmss-nginx-prod 2 rg-nginx-gallery nginx_monitor_gallery
```

**Output**:
- Load-balanced VMSS with health monitoring
- Intelligent autoscaling based on both CPU and HTTP request rates
- Metrics flowing to Azure Monitor Custom Metrics namespace `Custom/NGINX`

**Autoscaling Rules Created**:
- **Scale Out**:
  - CPU > 70% (5min avg) OR nginx_requests_per_second > 200 (5min avg)
  - Action: +1 instance
- **Scale In**:
  - CPU < 30% (5min avg) AND nginx_requests_per_second < 200 (3min avg)
  - Action: -1 instance

---

## 🔄 Complete Deployment Workflow

### For Development/Testing:
```bash
# Step 0: Create development VM
./0-deploy-vm.sh rg-nginx-dev northeurope ~/.ssh/id_rsa.pub vm-nginx-dev

# Test and configure your application
# Access: SSH to VM and test the monitoring stack
```

### For Production Deployment:
```bash
# Step 0: Create baseline VM
./0-deploy-vm.sh rg-nginx-base northeurope ~/.ssh/id_rsa.pub vm-nginx-base

# Step 1: Capture custom image (VM will be generalized)
./1-create-image-gallery.sh rg-nginx-gallery northeurope nginx_monitor_gallery rg-nginx-base vm-nginx-base

# Step 2.2: Deploy production VMSS with autoscaling
./2.2-deploy-vmss-from-image.sh rg-nginx-prod northeurope ~/.ssh/id_rsa.pub vmss-nginx-prod 2 rg-nginx-gallery nginx_monitor_gallery
```

### For Single Production VM:
```bash
# Steps 0 & 1 same as above...

# Step 2.1: Deploy single production VM
./2.1-deploy-vm-from-image.sh rg-nginx-single northeurope ~/.ssh/id_rsa.pub vm-nginx-single rg-nginx-gallery nginx_monitor_gallery
```

## 📊 Key Benefits of This Approach

### Why Use Custom Images?
- **Faster deployment**: ~2 minutes vs ~10 minutes with cloud-init
- **Consistent configuration**: Same setup across all instances
- **Reduced failure points**: Pre-tested, working configuration
- **Better scaling**: VMSS instances start faster during autoscaling events

### Why This Deployment Pattern?
1. **Step 0**: Perfect for development and creating your baseline
2. **Step 1**: Creates reusable, tested image once
3. **Step 2.1**: Single production VM for smaller workloads
4. **Step 2.2**: Scalable VMSS with intelligent autoscaling for production

## 🔍 Monitoring & Validation

After deployment, validate the setup:

```bash
# Check VMSS instances
az vmss list-instances --resource-group rg-nginx-prod --name vmss-nginx-prod

# Test load balancer endpoint
curl http://<load-balancer-ip>/health

# View custom metrics in Azure Portal:
# Navigate to VMSS → Monitoring → Metrics → Custom/NGINX namespace
```

## 🚨 Important Notes

1. **Resource Groups**: Each script creates its own resource group with unique suffixes
2. **Image Capture**: Step 1 will generalize and deallocate the source VM permanently
3. **Prerequisites**: Ensure Azure CLI is installed and you're logged in (`az login`)
4. **SSH Keys**: Make sure your SSH public key exists at the specified path
5. **Permissions**: Your Azure account needs Contributor access for resource creation
6. **Custom Metrics**: May take 5-10 minutes to appear in Azure Monitor after deployment

## 📁 Generated Resources

Each deployment creates these resource types:
- Resource Groups (with unique suffixes)
- Virtual Networks and Subnets
- Network Security Groups with HTTP/SSH rules
- Managed Identities with monitoring permissions
- Public IPs (single VM) or Load Balancers (VMSS)
- Custom autoscaling profiles with both CPU and application-aware rules

The result is a production-ready, scalable NGINX monitoring infrastructure that bridges application metrics with Azure's native autoscaling capabilities.

## 🛠️ Troubleshooting

If you encounter issues with VM deployment, cloud-init, or service startup, see [DEBUGVM.md](DEBUGVM.md) for comprehensive debugging steps and common solutions.