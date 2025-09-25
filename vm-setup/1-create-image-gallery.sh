#!/bin/bash

# Azure Shared Image Gallery Setup and Image Capture Script
# This script creates a Shared Image Gallery and captures a VM image for the NGINX Monitor stack

set -e

# Generate unique suffix for resource names
UNIQUE_SUFFIX=$(date +%s | tail -c 8)

# Script parameters
RESOURCE_GROUP=${1:-"rg-nginx-image-gallery-${UNIQUE_SUFFIX}"}
LOCATION=${2:-"northeurope"}

# Extract suffix from resource group name for consistency, or use unique suffix
if [[ "$RESOURCE_GROUP" =~ -([^-]+)$ ]]; then
    RG_SUFFIX=${BASH_REMATCH[1]}
else
    RG_SUFFIX=${UNIQUE_SUFFIX}
fi

GALLERY_NAME=${3:-"nginx_monitor_gallery_${RG_SUFFIX}"}
SOURCE_VM_RG=${4:-""}
SOURCE_VM_NAME=${5:-""}

# Image configuration
IMAGE_DEF_NAME="nginx-monitor-ubuntu-2404"
IMAGE_VERSION="1.0.0"
PUBLISHER="NginxMonitor"
OFFER="NginxMonitorStack"
SKU="Ubuntu-24.04-LTS"

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

    print_success "Prerequisites check passed"
}

# Validate source VM parameters
validate_source_vm() {
    if [[ -z "$SOURCE_VM_RG" ]] || [[ -z "$SOURCE_VM_NAME" ]]; then
        print_error "Source VM resource group and name are required"
        echo "Usage: $0 [gallery_rg] [location] [gallery_name] <source_vm_rg> <source_vm_name>"
        echo ""
        echo "Example: $0 rg-images northeurope my_gallery rg-nginx-monitor-test vm-nginx-monitor"
        exit 1
    fi

    # Check if source VM exists
    if ! az vm show --resource-group "$SOURCE_VM_RG" --name "$SOURCE_VM_NAME" &> /dev/null; then
        print_error "Source VM '$SOURCE_VM_NAME' not found in resource group '$SOURCE_VM_RG'"
        exit 1
    fi

    print_success "Source VM validated: $SOURCE_VM_NAME in $SOURCE_VM_RG"
}

# Create resource group for image gallery
create_resource_group() {
    print_status "Creating resource group: $RESOURCE_GROUP"

    if az group show --name "$RESOURCE_GROUP" &> /dev/null; then
        print_warning "Resource group $RESOURCE_GROUP already exists"
    else
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION"
        print_success "Created resource group: $RESOURCE_GROUP"
    fi
}

# Create Shared Image Gallery
create_image_gallery() {
    print_status "Creating Shared Image Gallery: $GALLERY_NAME"

    az sig create \
        --resource-group "$RESOURCE_GROUP" \
        --gallery-name "$GALLERY_NAME" \
        --location "$LOCATION" 

    print_success "Created Shared Image Gallery: $GALLERY_NAME"
}

# Create Image Definition
create_image_definition() {
    print_status "Creating image definition: $IMAGE_DEF_NAME"

    az sig image-definition create \
        --resource-group "$RESOURCE_GROUP" \
        --gallery-name "$GALLERY_NAME" \
        --gallery-image-definition "$IMAGE_DEF_NAME" \
        --publisher "$PUBLISHER" \
        --offer "$OFFER" \
        --sku "$SKU" \
        --os-type "Linux" \
        --os-state "Generalized" \
        --hyper-v-generation "V2" \
        --location "$LOCATION" \
        --description "Ubuntu 24.04 LTS with NGINX Azure Monitor Stack pre-installed" \
        --features SecurityType=TrustedLaunch \
        --architecture x64

    print_success "Created image definition: $IMAGE_DEF_NAME"
}

# Prepare source VM for imaging
prepare_source_vm() {
    print_status "Preparing source VM for imaging..."

    # Stop the VM
    print_status "Stopping VM: $SOURCE_VM_NAME"
    az vm stop --resource-group "$SOURCE_VM_RG" --name "$SOURCE_VM_NAME"

    # Deallocate the VM
    print_status "Deallocating VM: $SOURCE_VM_NAME"
    az vm deallocate --resource-group "$SOURCE_VM_RG" --name "$SOURCE_VM_NAME"

    # Generalize the VM
    print_status "Generalizing VM: $SOURCE_VM_NAME"
    az vm generalize --resource-group "$SOURCE_VM_RG" --name "$SOURCE_VM_NAME"

    print_success "VM prepared for imaging"
}

# Create image version from source VM
create_image_version() {
    print_status "Creating image version: $IMAGE_VERSION"

    # Get the source VM resource ID
    SOURCE_VM_ID=$(az vm show \
        --resource-group "$SOURCE_VM_RG" \
        --name "$SOURCE_VM_NAME" \
        --query id \
        --output tsv)

    print_status "Source VM ID: $SOURCE_VM_ID"

    # Create the image version
    az sig image-version create \
        --resource-group "$RESOURCE_GROUP" \
        --gallery-name "$GALLERY_NAME" \
        --gallery-image-definition "$IMAGE_DEF_NAME" \
        --gallery-image-version "$IMAGE_VERSION" \
        --virtual-machine "$SOURCE_VM_ID" \
        --location "$LOCATION" \
        --replica-count 1 \
        --target-regions "$LOCATION" 

    print_success "Created image version: $IMAGE_VERSION"
}

# Set up image permissions
setup_permissions() {
    print_status "Setting up image gallery permissions..."

    # Get the gallery resource ID
    GALLERY_ID=$(az sig show \
        --resource-group "$RESOURCE_GROUP" \
        --gallery-name "$GALLERY_NAME" \
        --query id \
        --output tsv)

    print_status "Gallery ID: $GALLERY_ID"

    # Note: By default, images in the same tenant are accessible
    # For cross-tenant or public access, additional configuration would be needed
    print_success "Image gallery permissions configured (tenant-wide access)"
}

# Get deployment outputs
get_outputs() {
    print_status "Getting image gallery information..."

    # Get gallery resource ID
    GALLERY_ID=$(az sig show \
        --resource-group "$RESOURCE_GROUP" \
        --gallery-name "$GALLERY_NAME" \
        --query id \
        --output tsv)

    # Get image definition resource ID
    IMAGE_DEF_ID=$(az sig image-definition show \
        --resource-group "$RESOURCE_GROUP" \
        --gallery-name "$GALLERY_NAME" \
        --gallery-image-definition "$IMAGE_DEF_NAME" \
        --query id \
        --output tsv)

    # Get image version resource ID
    IMAGE_VERSION_ID=$(az sig image-version show \
        --resource-group "$RESOURCE_GROUP" \
        --gallery-name "$GALLERY_NAME" \
        --gallery-image-definition "$IMAGE_DEF_NAME" \
        --gallery-image-version "$IMAGE_VERSION" \
        --query id \
        --output tsv)

    echo ""
    echo "======================================"
    echo "🎉 IMAGE GALLERY SETUP COMPLETED!"
    echo "======================================"
    echo ""
    echo "📊 Gallery Information:"
    echo "  Name: $GALLERY_NAME"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo ""
    echo "🖼️ Image Definition:"
    echo "  Name: $IMAGE_DEF_NAME"
    echo "  Publisher: $PUBLISHER"
    echo "  Offer: $OFFER"
    echo "  SKU: $SKU"
    echo ""
    echo "📦 Image Version:"
    echo "  Version: $IMAGE_VERSION"
    echo "  Source VM: $SOURCE_VM_NAME ($SOURCE_VM_RG)"
    echo ""
    echo "🔗 Resource IDs:"
    echo "  Gallery: $GALLERY_ID"
    echo "  Image Definition: $IMAGE_DEF_ID"
    echo "  Image Version: $IMAGE_VERSION_ID"
    echo ""
    echo "🚀 Deployment Commands:"
    echo "  # Deploy new VM from custom image:"
    echo "  az vm create \\"
    echo "    --resource-group <your-rg> \\"
    echo "    --name <vm-name> \\"
    echo "    --image \"$IMAGE_VERSION_ID\" \\"
    echo "    --admin-username azureuser \\"
    echo "    --generate-ssh-keys"
    echo ""
    echo "  # Or use in ARM/Bicep templates:"
    echo "  imageReference:"
    echo "    id: $IMAGE_VERSION_ID"
    echo ""
    echo "📋 Next Steps:"
    echo "  1. Test the image by creating a new VM"
    echo "  2. Verify NGINX Monitor stack starts automatically"
    echo "  3. Create additional image versions as needed"
    echo "  4. Update deployment scripts to use the custom image"
    echo ""
    echo "🔄 Deploy VM from Custom Image (Next Step):"
    echo "  Deploy a single VM from this custom image:"
    echo ""
    echo "  ./2.1-deploy-vm-from-image.sh \\"
    echo "      rg-nginx-prod-${RG_SUFFIX} \\"
    echo "      $LOCATION \\"
    echo "      ~/.ssh/id_rsa.pub \\"
    echo "      vm-nginx-prod-${RG_SUFFIX} \\"
    echo "      $RESOURCE_GROUP \\"
    echo "      $GALLERY_NAME"
    echo ""
    echo "🔄 Deploy VMSS from Custom Image (Alternative):"
    echo "  Deploy a Virtual Machine Scale Set from this custom image:"
    echo ""
    echo "  ./2.2-deploy-vmss-from-image.sh \\"
    echo "      rg-nginx-vmss-${RG_SUFFIX} \\"
    echo "      $LOCATION \\"
    echo "      ~/.ssh/id_rsa.pub \\"
    echo "      vmss-nginx-prod-${RG_SUFFIX} \\"
    echo "      3 \\"
    echo "      $RESOURCE_GROUP \\"
    echo "      $GALLERY_NAME"
    echo ""
}

# Display usage information
usage() {
    echo "Usage: $0 [gallery_rg] [location] [gallery_name] <source_vm_rg> <source_vm_name>"
    echo ""
    echo "Parameters:"
    echo "  gallery_rg       Resource group for the image gallery (optional)"
    echo "  location         Azure region (optional, default: northeurope)"
    echo "  gallery_name     Name of the Shared Image Gallery (optional)"
    echo "  source_vm_rg     Resource group of the source VM (required)"
    echo "  source_vm_name   Name of the source VM to capture (required)"
    echo ""
    echo "Example:"
    echo "  $0 rg-images northeurope my_gallery rg-nginx-monitor-test vm-nginx-monitor"
    echo ""
    echo "Note: The source VM will be stopped, deallocated, and generalized during this process."
}

# Main execution
main() {
    echo "🚀 Starting Azure Shared Image Gallery setup and VM image capture"
    echo "Parameters:"
    echo "  Gallery Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Gallery Name: $GALLERY_NAME"
    echo "  Source VM Resource Group: $SOURCE_VM_RG"
    echo "  Source VM Name: $SOURCE_VM_NAME"
    echo ""

    # Show usage if missing required parameters
    if [[ $# -lt 2 ]]; then
        print_error "Missing required parameters"
        echo ""
        usage
        exit 1
    fi

    check_prerequisites
    validate_source_vm
    create_resource_group
    create_image_gallery
    create_image_definition
    prepare_source_vm
    create_image_version
    setup_permissions
    get_outputs

    print_success "Image gallery setup completed successfully!"
}

# Run main function with all parameters
main "$@"