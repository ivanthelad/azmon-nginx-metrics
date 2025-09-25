#!/bin/bash

# Azure Autoscale Rules for NGINX based on Custom Metrics
# This script creates scale-out and scale-in rules based on custom NGINX metrics

# Variables - Update these for your environment
RESOURCE_GROUP="rg-nginx-vmss"
VMSS_NAME="vmss-nginx-prod"

# Auto-discover or create autoscale settings
echo "Checking for existing autoscale settings..."
EXISTING_AUTOSCALE=$(az monitor autoscale list --resource-group "$RESOURCE_GROUP" --query "[?targetResourceUri=='/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/virtualMachineScaleSets/$VMSS_NAME'].name" -o tsv)

if [ -n "$EXISTING_AUTOSCALE" ]; then
    AUTOSCALE_NAME="$EXISTING_AUTOSCALE"
    echo "✓ Found existing autoscale setting: $AUTOSCALE_NAME"
else
    AUTOSCALE_NAME="autoscale-$VMSS_NAME"
    echo "Creating new autoscale setting: $AUTOSCALE_NAME"

    az monitor autoscale create \
      --resource-group "$RESOURCE_GROUP" \
      --resource "$VMSS_NAME" \
      --resource-type Microsoft.Compute/virtualMachineScaleSets \
      --name "$AUTOSCALE_NAME" \
      --min-count 1 \
      --max-count 4 \
      --count 1

    if [ $? -eq 0 ]; then
        echo "✓ Autoscale setting created successfully"
    else
        echo "✗ Failed to create autoscale setting"
        exit 1
    fi
fi

# Scale-out rule: Add 2 instances when nginx requests per second > 200 averaged over 5 minutes
echo "Creating scale-out rule for high request rate..."
az monitor autoscale rule create \
  --resource-group "$RESOURCE_GROUP" \
  --autoscale-name "$AUTOSCALE_NAME" \
  --scale out 1 \
  --condition "[\"Custom/NGINX\"] nginx_requests_per_second > 200 avg 5m" \
  --cooldown 3

if [ $? -eq 0 ]; then
    echo "✓ Scale-out rule created successfully"
else
    echo "✗ Failed to create scale-out rule"
    exit 1
fi

# Scale-in rule: Remove 1 instance when nginx requests per second < 200 averaged over 3 minutes
echo "Creating scale-in rule for low request rate..."
az monitor autoscale rule create \
  --resource-group "$RESOURCE_GROUP" \
  --autoscale-name "$AUTOSCALE_NAME" \
  --scale in 1 \
  --condition "[\"Custom/NGINX\"] nginx_requests_per_second < 200 avg 3m" \
  --cooldown 3

if [ $? -eq 0 ]; then
    echo "✓ Scale-in rule created successfully"
else
    echo "✗ Failed to create scale-in rule"
    exit 1
fi

echo "Both autoscale rules have been created successfully!"
echo ""
echo "Scale-out: +1 instances when Custom/NGINX RPS > 200 (5 min average, 3 min cooldown)"
echo "Scale-in:  -1 instance when Custom/NGINX RPS < 200 (3 min average, 3 min cooldown)"