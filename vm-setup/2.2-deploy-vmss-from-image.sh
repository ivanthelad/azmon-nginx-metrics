#!/bin/bash

# Azure VMSS Deployment Script for NGINX Azure Monitor Stack (Using Custom Image)
# Ubuntu 24.04 LTS with Docker, Azure Monitor Agent, and Load Balancer
# Uses pre-built custom image instead of cloud-init for faster deployment

set -e

# Generate unique suffix for resource group
UNIQUE_SUFFIX=$(date +%s | tail -c 8)

# Script parameters
RESOURCE_GROUP=${1:-"nginx-monitor-vmss-rg-${UNIQUE_SUFFIX}"}
LOCATION=${2:-"northeurope"}
SSH_KEY_PATH=${3:-"~/.ssh/id_rsa.pub"}
VMSS_NAME=${4:-"vmss-nginx-monitor"}
INSTANCE_COUNT=${5:-"2"}

# Custom image configuration
IMAGE_GALLERY_RG=${6:-"nginx-monitor-rg-8529242"}
IMAGE_GALLERY_NAME=${7:-"nginx_monitor_gallery"}
IMAGE_DEFINITION=${8:-"nginx-monitor-ubuntu-2404"}
IMAGE_VERSION=${9:-"1.0.0"}

# Configuration variables
VM_SIZE="Standard_B2s"
ADMIN_USERNAME="azureuser"
VNET_NAME="vnet-nginx-monitor"
SUBNET_NAME="subnet-default"
NSG_NAME="nsg-nginx-monitor"
LB_NAME="lb-nginx-monitor"
LB_PUBLIC_IP_NAME="pip-lb-nginx-monitor"
BACKEND_POOL_NAME="be-nginx-pool"
HEALTH_PROBE_NAME="hp-nginx-health"
LB_RULE_NAME="lr-nginx-http"
MANAGED_IDENTITY_NAME="id-nginx-monitor"
LOG_ANALYTICS_WORKSPACE="law-nginx-monitor"
DCR_NAME="dcr-nginx-monitor"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."

    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        print_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi

    # Check if SSH key exists
    if [[ ! -f "${SSH_KEY_PATH/#\~/$HOME}" ]]; then
        print_error "SSH public key not found at: $SSH_KEY_PATH"
        print_status "Generate one with: ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa"
        exit 1
    fi

    print_success "Prerequisites check passed"
}

# Validate custom image parameters
validate_custom_image() {
    if [[ -z "$IMAGE_GALLERY_RG" ]] || [[ -z "$IMAGE_GALLERY_NAME" ]]; then
        print_error "Image gallery resource group and name are required"
        echo "Usage: $0 [vmss_rg] [location] [ssh_key] [vmss_name] [instance_count] <image_gallery_rg> <image_gallery_name> [image_def] [image_version]"
        echo ""
        echo "Example: $0 rg-test northeurope ~/.ssh/id_rsa.pub vmss-test 3 rg-images my_gallery"
        exit 1
    fi

    # Verify the custom image exists
    if ! az sig image-version show \
        --resource-group "$IMAGE_GALLERY_RG" \
        --gallery-name "$IMAGE_GALLERY_NAME" \
        --gallery-image-definition "$IMAGE_DEFINITION" \
        --gallery-image-version "$IMAGE_VERSION" &> /dev/null; then
        print_error "Custom image not found: $IMAGE_DEFINITION:$IMAGE_VERSION in gallery $IMAGE_GALLERY_NAME"
        exit 1
    fi

    print_success "Custom image validated: $IMAGE_DEFINITION:$IMAGE_VERSION"
}

# Get custom image resource ID
get_image_id() {
    print_status "Getting custom image resource ID..."

    IMAGE_ID=$(az sig image-version show \
        --resource-group "$IMAGE_GALLERY_RG" \
        --gallery-name "$IMAGE_GALLERY_NAME" \
        --gallery-image-definition "$IMAGE_DEFINITION" \
        --gallery-image-version "$IMAGE_VERSION" \
        --query id \
        --output tsv)

    print_success "Image ID: $IMAGE_ID"
}

# Create resource group
create_resource_group() {
    print_status "Creating resource group: $RESOURCE_GROUP"

    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
        print_success "Created resource group: $RESOURCE_GROUP"
    fi
}

# Create virtual network and subnet
create_network() {
    print_status "Creating virtual network: $VNET_NAME"

    # Create VNet
    az network vnet create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VNET_NAME" \
        --address-prefix "10.0.0.0/16" \
        --subnet-name "$SUBNET_NAME" \
        --subnet-prefix "10.0.0.0/24" \
        --location "$LOCATION"

    print_success "Created virtual network and subnet"
}

# Create Network Security Group with rules
create_nsg() {
    print_status "Creating Network Security Group: $NSG_NAME"

    # Create NSG
    az network nsg create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NSG_NAME" \
        --location "$LOCATION"

    # Allow HTTP (port 80)
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "AllowHTTP" \
        --protocol Tcp \
        --priority 1000 \
        --destination-port-range 80 \
        --access Allow \
        --description "Allow HTTP traffic on port 80"


    # Associate NSG with subnet
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --network-security-group "$NSG_NAME"

    print_success "Created NSG with security rules"
}

# Create load balancer and public IP
create_load_balancer() {
    print_status "Creating load balancer and public IP..."

    # Create public IP for load balancer
    az network public-ip create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LB_PUBLIC_IP_NAME" \
        --sku Standard \
        --allocation-method Static \
        --location "$LOCATION"

    # Create load balancer
    az network lb create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LB_NAME" \
        --sku Standard \
        --public-ip-address "$LB_PUBLIC_IP_NAME" \
        --frontend-ip-name "frontend" \
        --backend-pool-name "$BACKEND_POOL_NAME" \
        --location "$LOCATION"

    # Create health probe for HTTP
    az network lb probe create \
        --resource-group "$RESOURCE_GROUP" \
        --lb-name "$LB_NAME" \
        --name "$HEALTH_PROBE_NAME" \
        --protocol Http \
        --port 80 \
        --path "/health"

    # Create load balancing rule for HTTP
    az network lb rule create \
        --resource-group "$RESOURCE_GROUP" \
        --lb-name "$LB_NAME" \
        --name "$LB_RULE_NAME" \
        --protocol Tcp \
        --frontend-port 80 \
        --backend-port 80 \
        --frontend-ip-name "frontend" \
        --backend-pool-name "$BACKEND_POOL_NAME" \
        --probe-name "$HEALTH_PROBE_NAME"


    print_success "Created load balancer with health probe and rules"
}

# Configure Azure resources for monitoring
configure_azure_monitoring() {
    print_status "Configuring Azure monitoring resources..."

    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)

    # Create user-assigned managed identity
    az identity create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MANAGED_IDENTITY_NAME" \
        --location "$LOCATION"

    # Get the principal ID for role assignments
    MANAGED_IDENTITY_PRINCIPAL_ID=$(az identity show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MANAGED_IDENTITY_NAME" \
        --query principalId \
        --output tsv)

    MANAGED_IDENTITY_ID=$(az identity show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MANAGED_IDENTITY_NAME" \
        --query id \
        --output tsv)

    # Assign Monitoring Metrics Publisher role at resource group scope
    az role assignment create \
        --assignee "$MANAGED_IDENTITY_PRINCIPAL_ID" \
        --role "Monitoring Contributor" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

    print_success "Configured Azure monitoring resources"
}

# Create virtual machine scale set from custom image
create_vmss_from_custom_image() {
    print_status "Creating virtual machine scale set from custom image: $VMSS_NAME"

    # Read SSH public key
    SSH_KEY_DATA=$(cat "${SSH_KEY_PATH/#\~/$HOME}")

    # Get the managed identity resource ID
    MANAGED_IDENTITY_ID=$(az identity show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MANAGED_IDENTITY_NAME" \
        --query id \
        --output tsv)

    # Create a cloud-init script for VMSS instances
    cat > /tmp/vmss-cloud-init.yaml << 'EOF'
#cloud-config
package_update: true

runcmd:
  # Wait for system to be ready
  - sleep 30

  # Get Azure metadata for this VMSS instance
  - SUBSCRIPTION_ID=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2021-02-01&format=text")
  - RESOURCE_GROUP=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/resourceGroupName?api-version=2021-02-01&format=text")
  - VMSS_NAME=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/vmScaleSetName?api-version=2021-02-01&format=text")
  - INSTANCE_ID=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-02-01&format=text")
  - LOCATION=$(curl -s -H "Metadata:true" "http://169.254.169.254/metadata/instance/compute/location?api-version=2021-02-01&format=text")

  # Update environment file with VMSS-specific configuration
  - |
    sudo tee /opt/nginx-monitor/.env > /dev/null << EOL
    # Azure Configuration for VMSS Instance
    AZURE_SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
    AZURE_RESOURCE_GROUP=${RESOURCE_GROUP}
    AZURE_RESOURCE_NAME=${INSTANCE_ID}
    AZURE_REGION=${LOCATION}

    # Use Managed Identity
    AZURE_USE_MANAGED_IDENTITY=true

    # Monitoring Configuration
    SCRAPE_INTERVAL=60

    # NGINX Configuration
    NGINX_WORKER_PROCESSES=auto
    NGINX_WORKER_CONNECTIONS=1024

    # Prometheus Exporter Configuration
    NGINX_STATUS_URL=http://nginx/nginx_status
    NGINX_JSON_URL=http://nginx/status_json
    EXPORTER_SCRAPE_INTERVAL=15
    EOL

  # Ensure correct ownership
  - sudo chown azureuser:azureuser /opt/nginx-monitor/.env
  - sudo chmod 600 /opt/nginx-monitor/.env

  # Restart the services to pick up new configuration
  - cd /opt/nginx-monitor
  - sudo systemctl daemon-reload
  - sudo systemctl restart nginx-monitor.service

  # Wait a bit and check service status
  - sleep 10
  - sudo systemctl is-active --quiet nginx-monitor.service && echo "VMSS instance configured successfully" || echo "Service failed to start"
EOF

    # Create VMSS from custom image
    az vmss create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --image "$IMAGE_ID" \
        --vm-sku "$VM_SIZE" \
        --admin-username "$ADMIN_USERNAME" \
        --ssh-key-values "$SSH_KEY_DATA" \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET_NAME" \
        --lb "$LB_NAME" \
        --backend-pool-name "$BACKEND_POOL_NAME" \
        --assign-identity "$MANAGED_IDENTITY_ID" \
        --instance-count "$INSTANCE_COUNT" \
        --upgrade-policy-mode Automatic \
        --orchestration-mode Uniform \
        --security-type TrustedLaunch \
        --enable-secure-boot true \
        --enable-vtpm true \
        --custom-data /tmp/vmss-cloud-init.yaml \
        --storage-sku Premium_LRS \
        --os-disk-size-gb 30 \
        --location "$LOCATION"

    # Clean up temporary cloud-init file
    rm /tmp/vmss-cloud-init.yaml

    print_success "Created virtual machine scale set from custom image"
}

# Configure auto-scaling for VMSS
configure_autoscaling() {
    print_status "Configuring auto-scaling for VMSS..."

    # Create autoscale profile
    az monitor autoscale create \
        --resource-group "$RESOURCE_GROUP" \
        --resource "$VMSS_NAME" \
        --resource-type Microsoft.Compute/virtualMachineScaleSets \
        --name "autoscale-$VMSS_NAME" \
        --min-count 1 \
        --max-count 4 \
        --count 1

    # Scale out rule (CPU > 70%)
    az monitor autoscale rule create \
        --resource-group "$RESOURCE_GROUP" \
        --autoscale-name "autoscale-$VMSS_NAME" \
        --condition "Percentage CPU > 70 avg 5m" \
        --scale out 1

    # Scale in rule (CPU < 30%)
    az monitor autoscale rule create \
        --resource-group "$RESOURCE_GROUP" \
        --autoscale-name "autoscale-$VMSS_NAME" \
        --condition "Percentage CPU < 30 avg 5m" \
        --scale in 1

    print_success "Configured CPU-based auto-scaling rules"
}

# Configure custom metrics auto-scaling for VMSS
configure_custom_metrics_autoscaling() {
    print_status "Configuring custom NGINX metrics auto-scaling..."

    # Scale-out rule: Add 1 instance when nginx requests per second > 200 averaged over 5 minutes
    print_status "Creating scale-out rule for high request rate..."
    az monitor autoscale rule create \
        --resource-group "$RESOURCE_GROUP" \
        --autoscale-name "autoscale-$VMSS_NAME" \
        --scale out 1 \
        --condition "[\"Custom/NGINX\"] nginx_requests_per_second > 200 avg 5m" \
        --cooldown 3

    if [ $? -eq 0 ]; then
        print_success "Scale-out rule created successfully"
    else
        print_warning "Failed to create scale-out rule - custom metrics may not be available yet"
    fi

    # Scale-in rule: Remove 1 instance when nginx requests per second < 200 averaged over 3 minutes
    print_status "Creating scale-in rule for low request rate..."
    az monitor autoscale rule create \
        --resource-group "$RESOURCE_GROUP" \
        --autoscale-name "autoscale-$VMSS_NAME" \
        --scale in 1 \
        --condition "[\"Custom/NGINX\"] nginx_requests_per_second < 200 avg 3m" \
        --cooldown 3

    if [ $? -eq 0 ]; then
        print_success "Scale-in rule created successfully"
    else
        print_warning "Failed to create scale-in rule - custom metrics may not be available yet"
    fi

    print_success "Custom metrics auto-scaling configuration complete"
}

# Get deployment outputs
get_outputs() {
    print_status "Getting deployment information..."

    # Get load balancer public IP address
    LB_PUBLIC_IP=$(az network public-ip show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$LB_PUBLIC_IP_NAME" \
        --query ipAddress \
        --output tsv)

    # Get VMSS instance information
    INSTANCE_IPS=$(az vmss list-instance-public-ips \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VMSS_NAME" \
        --query "[].ipAddress" \
        --output tsv)

    echo ""
    echo "========================================"
    echo "🎉 VMSS CUSTOM IMAGE DEPLOYMENT COMPLETED!"
    echo "========================================"
    echo ""
    echo "📊 VMSS Information:"
    echo "  Name: $VMSS_NAME"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Instance Count: $INSTANCE_COUNT"
    echo "  VM Size: $VM_SIZE"
    echo "  Custom Image: $IMAGE_DEFINITION:$IMAGE_VERSION"
    echo ""
    echo "🌐 Load Balancer Information:"
    echo "  Public IP: $LB_PUBLIC_IP"
    echo "  Admin Username: $ADMIN_USERNAME"
    echo ""
    echo "🌍 Service Endpoints (Load Balanced):"
    echo "  NGINX Health: http://$LB_PUBLIC_IP/health"
    echo "  NGINX API Fast: http://$LB_PUBLIC_IP/api/v1/fast"
    echo "  Note: Prometheus metrics (port 9113) available on individual instances"
    echo ""
    echo "🔧 SSH Access:"
    echo "  Direct SSH access not configured (load balancer only handles HTTP traffic)"
    echo "  Use Azure Bastion or VPN for secure access to instances"
    echo ""
    echo "🔍 Individual Instance IPs:"
    i=0
    for ip in $INSTANCE_IPS; do
        echo "  Instance $i: $ip"
        ((i++))
    done
    echo ""
    echo "📋 Next Steps:"
    echo "  1. Services should be running automatically from the custom image"
    echo "  2. Test load balanced endpoints above to verify everything is working"
    echo "  3. Check Azure Monitor for custom metrics from all instances"
    echo "  4. Monitor auto-scaling behavior under load"
    echo ""
    echo "🔄 VMSS Management:"
    echo "  az vmss list-instances -g $RESOURCE_GROUP -n $VMSS_NAME"
    echo "  az vmss scale -g $RESOURCE_GROUP -n $VMSS_NAME --new-capacity 5"
    echo "  az vmss restart -g $RESOURCE_GROUP -n $VMSS_NAME"
    echo ""
    echo "📈 Auto-scaling Rules:"
    echo "  Min instances: 1, Max instances: 4"
    echo "  CPU-based:"
    echo "    • Scale out: CPU > 70% (5min avg, +1 instance)"
    echo "    • Scale in: CPU < 30% (5min avg, -1 instance)"
    echo "  Custom NGINX Metrics-based:"
    echo "    • Scale out: nginx_requests_per_second > 200 (5min avg, +1 instance, 3min cooldown)"
    echo "    • Scale in: nginx_requests_per_second < 200 (3min avg, -1 instance, 3min cooldown)"
    echo ""
}

# Display usage information
usage() {
    echo "Usage: $0 [vmss_rg] [location] [ssh_key] [vmss_name] [instance_count] <image_gallery_rg> <image_gallery_name> [image_def] [image_version]"
    echo ""
    echo "Parameters:"
    echo "  vmss_rg          Resource group for the VMSS (optional)"
    echo "  location         Azure region (optional, default: northeurope)"
    echo "  ssh_key          SSH public key path (optional, default: ~/.ssh/id_rsa.pub)"
    echo "  vmss_name        Name of the VMSS (optional, default: vmss-nginx-monitor)"
    echo "  instance_count   Initial number of instances (optional, default: 2)"
    echo "  image_gallery_rg Resource group of the image gallery (required)"
    echo "  image_gallery_name Name of the Shared Image Gallery (required)"
    echo "  image_def        Image definition name (optional, default: nginx-monitor-ubuntu-2404)"
    echo "  image_version    Image version (optional, default: 1.0.0)"
    echo ""
    echo "Example:"
    echo "  $0 rg-prod northeurope ~/.ssh/id_rsa.pub vmss-prod 3 rg-images my_gallery"
    echo ""
}

# Main execution
main() {
    echo "🚀 Starting VMSS deployment from custom NGINX Monitor image"
    echo "Parameters:"
    echo "  VMSS Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  VMSS Name: $VMSS_NAME"
    echo "  Instance Count: $INSTANCE_COUNT"
    echo "  Image Gallery RG: $IMAGE_GALLERY_RG"
    echo "  Image Gallery: $IMAGE_GALLERY_NAME"
    echo "  Image Definition: $IMAGE_DEFINITION"
    echo "  Image Version: $IMAGE_VERSION"
    echo ""

    # Show usage if missing required parameters
    if [[ $# -lt 2 ]]; then
        print_error "Missing required parameters"
        echo ""
        usage
        exit 1
    fi

    check_prerequisites
    validate_custom_image
    get_image_id
    create_resource_group
    create_network
    create_nsg
    create_load_balancer
    configure_azure_monitoring
    create_vmss_from_custom_image
    configure_autoscaling
    configure_custom_metrics_autoscaling

    # Wait a bit for the VMSS to fully deploy
    print_status "Waiting for VMSS instances to fully deploy and configure..."
    sleep 120

    get_outputs

    print_success "VMSS custom image deployment completed successfully!"
}

# Run main function with all parameters
main "$@"