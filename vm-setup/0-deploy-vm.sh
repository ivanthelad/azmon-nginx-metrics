#!/bin/bash

# Azure VM Deployment Script for NGINX Azure Monitor Stack
# Ubuntu 24.04 LTS with Docker, Azure Monitor Agent, and JIT SSH Access

set -e

# Generate unique suffix for resource group
UNIQUE_SUFFIX=$(date +%s | tail -c 8)

# Script parameters
RESOURCE_GROUP=${1:-"nginx-monitor-rg-${UNIQUE_SUFFIX}"}
LOCATION=${2:-"northeurope"}
SSH_KEY_PATH=${3:-"~/.ssh/id_rsa.pub"}

# Extract suffix from resource group name for consistency
if [[ "$RESOURCE_GROUP" =~ -([^-]+)$ ]]; then
    RG_SUFFIX=${BASH_REMATCH[1]}
else
    RG_SUFFIX=${UNIQUE_SUFFIX}
fi

VM_NAME=${4:-"vm-nginx-monitor-${RG_SUFFIX}"}

# Configuration variables
VM_SIZE="Standard_B2s"
VM_IMAGE="Ubuntu2404"
ADMIN_USERNAME="azureuser"
VNET_NAME="vnet-nginx-monitor"
SUBNET_NAME="subnet-default"
NSG_NAME="nsg-nginx-monitor"
PUBLIC_IP_NAME="pip-nginx-monitor"
NIC_NAME="nic-nginx-monitor"
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

# Create managed identity
create_managed_identity() {
    print_status "Creating user-assigned managed identity: $MANAGED_IDENTITY_NAME"

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

    print_success "Created managed identity with Principal ID: $MANAGED_IDENTITY_PRINCIPAL_ID"
}

# Create Log Analytics workspace
create_log_analytics() {
    print_status "Creating Log Analytics workspace: $LOG_ANALYTICS_WORKSPACE"

    az monitor log-analytics workspace create \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --location "$LOCATION" \
        --sku "PerGB2018"

    LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query id \
        --output tsv)

    print_success "Created Log Analytics workspace"
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


    # Deny direct SSH (will use JIT instead)
    az network nsg rule create \
        --resource-group "$RESOURCE_GROUP" \
        --nsg-name "$NSG_NAME" \
        --name "DenySSHDirect" \
        --protocol Tcp \
        --priority 4000 \
        --destination-port-range 22 \
        --access Deny \
        --description "Deny direct SSH access - use JIT instead"

    # Associate NSG with subnet
    az network vnet subnet update \
        --resource-group "$RESOURCE_GROUP" \
        --vnet-name "$VNET_NAME" \
        --name "$SUBNET_NAME" \
        --network-security-group "$NSG_NAME"

    print_success "Created NSG with security rules"
}

# Create public IP
create_public_ip() {
    print_status "Creating public IP: $PUBLIC_IP_NAME"

    az network public-ip create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PUBLIC_IP_NAME" \
        --sku Standard \
        --allocation-method Static \
        --location "$LOCATION"

    print_success "Created public IP"
}

# Create network interface
create_nic() {
    print_status "Creating network interface: $NIC_NAME"

    az network nic create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$NIC_NAME" \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET_NAME" \
        --public-ip-address "$PUBLIC_IP_NAME" \
        --location "$LOCATION"

    print_success "Created network interface"
}

# Create virtual machine
create_vm() {
    print_status "Creating virtual machine: $VM_NAME"

    # Read SSH public key
    SSH_KEY_DATA=$(cat "${SSH_KEY_PATH/#\~/$HOME}")

    # Get script directory
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Create cloud-init file with environment substitution
    CLOUD_INIT_FILE="/tmp/cloud-init-${VM_NAME}.yaml"
    sed "s/\${subscription_id}/$(az account show --query id -o tsv)/g; \
         s/\${resource_group}/$RESOURCE_GROUP/g; \
         s/\${vm_name}/$VM_NAME/g; \
         s/\${region}/$LOCATION/g" \
         "$SCRIPT_DIR/cloud-init.yaml" > "$CLOUD_INIT_FILE"

    # Create VM
    az vm create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --image "$VM_IMAGE" \
        --size "$VM_SIZE" \
        --admin-username "$ADMIN_USERNAME" \
        --ssh-key-values "$SSH_KEY_DATA" \
        --nics "$NIC_NAME" \
        --custom-data "$CLOUD_INIT_FILE" \
        --assign-identity "$MANAGED_IDENTITY_ID" \
        --location "$LOCATION" \
        --storage-sku Premium_LRS \
        --os-disk-size-gb 30

    # Clean up temporary file
    rm "$CLOUD_INIT_FILE"

    print_success "Created virtual machine"
}

# Install Azure Monitor Agent
install_ama() {
    print_status "Installing Azure Monitor Agent extension"

    az vm extension set \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$VM_NAME" \
        --name AzureMonitorLinuxAgent \
        --publisher Microsoft.Azure.Monitor \
        --version 1.25 \
        --enable-auto-upgrade true

    print_success "Installed Azure Monitor Agent"
}

# Create Data Collection Rule
create_dcr() {
    print_status "Creating Data Collection Rule: $DCR_NAME"

    # Create a temporary DCR configuration file
    DCR_CONFIG_FILE="/tmp/dcr-${VM_NAME}.json"

    cat > "$DCR_CONFIG_FILE" << EOF
{
  "location": "$LOCATION",
  "properties": {
    "dataSources": {
      "performanceCounters": [
        {
          "name": "VMInsightsPerfCounters",
          "streams": ["Microsoft-InsightsMetrics"],
          "scheduledTransferPeriod": "PT1M",
          "samplingFrequencyInSeconds": 60,
          "counterSpecifiers": [
            "\\\\Processor Information(_Total)\\\\% Processor Time",
            "\\\\Memory\\\\% Committed Bytes In Use",
            "\\\\Memory\\\\Available Bytes",
            "\\\\LogicalDisk(_Total)\\\\% Disk Time",
            "\\\\LogicalDisk(_Total)\\\\Disk Bytes/sec",
            "\\\\Network Interface(*)\\\\Bytes Total/sec"
          ]
        }
      ],
      "syslog": [
        {
          "name": "sysLogsDataSource",
          "streams": ["Microsoft-Syslog"],
          "facilityNames": ["auth", "authpriv", "daemon", "kern", "syslog"],
          "logLevels": ["Warning", "Error", "Critical", "Alert", "Emergency"]
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "workspaceResourceId": "$LOG_ANALYTICS_ID",
          "name": "VMInsightsPerf-Logs-Dest"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": ["Microsoft-InsightsMetrics"],
        "destinations": ["VMInsightsPerf-Logs-Dest"]
      },
      {
        "streams": ["Microsoft-Syslog"],
        "destinations": ["VMInsightsPerf-Logs-Dest"]
      }
    ]
  }
}
EOF

    # Create DCR
    az monitor data-collection rule create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DCR_NAME" \
        --rule-file "$DCR_CONFIG_FILE"

    # Get DCR ID
    DCR_ID=$(az monitor data-collection rule show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DCR_NAME" \
        --query id \
        --output tsv)

    # Associate DCR with VM
    VM_ID=$(az vm show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --query id \
        --output tsv)

    az monitor data-collection rule association create \
        --name "configurationAccessEndpoint" \
        --rule-id "$DCR_ID" \
        --resource "$VM_ID"

    # Clean up temporary file
    rm "$DCR_CONFIG_FILE"

    print_success "Created and associated Data Collection Rule"
}

# Assign roles to managed identity
assign_roles() {
    print_status "Assigning roles to managed identity"

    # Get subscription ID
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)

    # Assign Monitoring Metrics Publisher role at resource group scope
    az role assignment create \
        --assignee "$MANAGED_IDENTITY_PRINCIPAL_ID" \
        --role "Monitoring Metrics Publisher" \
        --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

    # Assign Log Analytics Contributor role to the workspace
    az role assignment create \
        --assignee "$MANAGED_IDENTITY_PRINCIPAL_ID" \
        --role "Log Analytics Contributor" \
        --scope "$LOG_ANALYTICS_ID"

    print_success "Assigned required roles to managed identity"
}

# Configure JIT access
configure_jit() {
    print_status "Configuring Just-In-Time (JIT) access"

    # Get VM resource ID
    VM_RESOURCE_ID=$(az vm show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$VM_NAME" \
        --query id \
        --output tsv)

    # Create JIT policy configuration
    JIT_POLICY_FILE="/tmp/jit-policy-${VM_NAME}.json"

    cat > "$JIT_POLICY_FILE" << EOF
{
  "virtualMachines": [
    {
      "id": "$VM_RESOURCE_ID",
      "ports": [
        {
          "number": 22,
          "protocol": "*",
          "allowedSourceAddressPrefix": "*",
          "maxRequestAccessDuration": "PT3H"
        }
      ]
    }
  ]
}
EOF

    # Create JIT access policy
    az security jit-policy upsert \
        --resource-group "$RESOURCE_GROUP" \
        --name "${VM_NAME}-jit-policy" \
        --virtual-machines "$JIT_POLICY_FILE"

    # Clean up temporary file
    rm "$JIT_POLICY_FILE"

    print_success "Configured JIT access policy"
}

# Get deployment outputs
get_outputs() {
    print_status "Getting deployment information..."

    # Get public IP address
    PUBLIC_IP=$(az network public-ip show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PUBLIC_IP_NAME" \
        --query ipAddress \
        --output tsv)

    # Get FQDN
    FQDN=$(az network public-ip show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$PUBLIC_IP_NAME" \
        --query dnsSettings.fqdn \
        --output tsv)

    # Get managed identity client ID
    MANAGED_IDENTITY_CLIENT_ID=$(az identity show \
        --resource-group "$RESOURCE_GROUP" \
        --name "$MANAGED_IDENTITY_NAME" \
        --query clientId \
        --output tsv)

    # Get Log Analytics workspace ID
    LOG_ANALYTICS_WORKSPACE_ID=$(az monitor log-analytics workspace show \
        --resource-group "$RESOURCE_GROUP" \
        --workspace-name "$LOG_ANALYTICS_WORKSPACE" \
        --query customerId \
        --output tsv)

    echo ""
    echo "======================================"
    echo "🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "======================================"
    echo ""
    echo "📊 VM Information:"
    echo "  Name: $VM_NAME"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  Size: $VM_SIZE"
    echo ""
    echo "🌐 Network Information:"
    echo "  Public IP: $PUBLIC_IP"
    echo "  FQDN: $FQDN"
    echo "  Admin Username: $ADMIN_USERNAME"
    echo ""
    echo "🔐 Security Information:"
    echo "  Managed Identity Client ID: $MANAGED_IDENTITY_CLIENT_ID"
    echo "  JIT SSH Access: Enabled (request access via Azure Portal)"
    echo ""
    echo "📈 Monitoring Information:"
    echo "  Log Analytics Workspace ID: $LOG_ANALYTICS_WORKSPACE_ID"
    echo "  Azure Monitor Agent: Installed"
    echo ""
    echo "🌍 Service Endpoints:"
    echo "  NGINX Health: http://$PUBLIC_IP/health"
    echo "  NGINX API Fast: http://$PUBLIC_IP/api/v1/fast"
    echo "  Note: Prometheus metrics (port 9113) and OpenTelemetry (port 8000) are only accessible internally"
    echo ""
    echo "🔧 SSH Access:"
    echo "  1. Request JIT access via Azure Portal"
    echo "  2. Once approved: ssh $ADMIN_USERNAME@$PUBLIC_IP"
    echo ""
    echo "📋 Next Steps:"
    echo "  1. Wait 5-10 minutes for cloud-init to complete"
    echo "  2. Test endpoints above to verify services are running"
    echo "  3. Check Azure Monitor for custom metrics"
    echo "  4. View logs: ssh into VM and run 'sudo journalctl -u nginx-monitor.service'"
    echo ""
    echo "🔄 Create Custom Image (Next Step):"
    echo "  Once the VM is configured and working properly, create a custom image:"
    echo ""
    echo "  ./1-create-image-gallery.sh \\"
    echo "      rg-nginx-images-${RG_SUFFIX} \\"
    echo "      $LOCATION \\"
    echo "      nginx_monitor_gallery_${RG_SUFFIX} \\"
    echo "      $RESOURCE_GROUP \\"
    echo "      $VM_NAME"
    echo ""
    echo "  This will capture the current VM as a reusable custom image."
    echo ""
}

# Main execution
main() {
    echo "🚀 Starting Azure VM deployment for NGINX Monitor stack"
    echo "Parameters:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  VM Name: $VM_NAME"
    echo "  SSH Key Path: $SSH_KEY_PATH"
    echo ""

    check_prerequisites
    create_resource_group
    create_managed_identity
    create_log_analytics
    create_network
    create_nsg
    create_public_ip
    create_nic
    create_vm
    install_ama
    create_dcr
    assign_roles
    get_outputs

    print_success "Deployment completed successfully!"
}

# Run main function
main "$@"