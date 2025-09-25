# Azure Monitor Metrics Collector

Collects Prometheus metrics from nginx-exporter and sends them to Azure Monitor Custom Metrics.

## Operation

- Scrapes Prometheus metrics from nginx-exporter endpoint (`/metrics`)
- Transforms metrics to Azure Monitor Custom Metrics format
- Sends to Azure Monitor REST API every 60 seconds (configurable)

## Configuration Discovery

### VM Mode
Uses Azure IMDS (Instance Metadata Service) to automatically discover:
- `subscription_id` - From IMDS `subscriptionId`
- `resource_group` - From IMDS `resourceGroupName`
- `resource_name` - From IMDS `name`
- `location` - From IMDS `location`

### VMSS Mode
Auto-detects VMSS instances and configures:
- `vmss_name` - From IMDS `vmScaleSetName`
- `instance_id` - From IMDS `name` (instance identifier)
- Uses VMSS name as target resource for metrics

## Authentication

Uses Azure Managed Identity by default:
- `AZURE_USE_MANAGED_IDENTITY=true` - Uses system-assigned managed identity
- Falls back to service principal if environment variables provided:
  - `AZURE_CLIENT_ID`
  - `AZURE_CLIENT_SECRET`
  - `AZURE_TENANT_ID`

## Environment Variables

- `PROMETHEUS_URL` - Metrics source (default: `http://nginx-exporter:9113/metrics`)
- `SCRAPE_INTERVAL` - Send frequency in seconds (default: `60`)
- `AZURE_USE_MANAGED_IDENTITY` - Use managed identity (default: `auto`)

## IMDS Integration

Calls Azure IMDS endpoint `http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01` to:
1. Determine if running on VM or VMSS instance
2. Extract resource configuration automatically
3. Set appropriate resource target for Custom Metrics API

## Health Check

```bash
docker-compose exec metrics-collector python azure_monitor_sender.py --health-check
```