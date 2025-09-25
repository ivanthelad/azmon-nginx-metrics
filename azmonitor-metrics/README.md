# NGINX Metrics Monitor for Azure

A comprehensive solution for collecting NGINX metrics via Prometheus exporter and sending them to Azure Monitor Custom Metrics for autoscaling and monitoring.

## 🎯 Features

- **Prometheus Integration**: Uses NGINX Prometheus exporter for accurate metrics collection
- **Azure Monitor Custom Metrics**: Sends metrics directly to Azure Monitor Metrics (not Log Analytics)
- **Robust Monitoring**: Handles failures, retries, and health checks
- **Easy Deployment**: Automated installation scripts and systemd service
- **Production Ready**: Logging, error handling, and graceful shutdown
- **Cost Effective**: Uses Azure Monitor Custom Metrics API (no Data Collection Rules needed)

## 📋 Components

1. **`install_nginx.sh`** - Installs and configures NGINX web server
2. **`install_nginx_exporter.sh`** - Installs and configures NGINX Prometheus exporter
3. **`prometheus_scraper.py`** - Scrapes metrics from Prometheus endpoint
4. **`azure_monitor_sender.py`** - Sends metrics to Azure Monitor
5. **`nginx_metrics_monitor.py`** - Main orchestration script with periodic execution
6. **`systemd_service.sh`** - Creates systemd service for production deployment
7. **`PREREQUISITES.md`** - Detailed prerequisites and setup requirements

## 🚀 Quick Start

### 0. Prerequisites
**First, read `PREREQUISITES.md` for detailed setup requirements including:**
- System requirements and dependencies
- Azure subscription and authentication setup
- Required environment variables
- Network and firewall configuration

### 1. Install NGINX Web Server

```bash
chmod +x install_nginx.sh
sudo ./install_nginx.sh
```

This will:
- Install NGINX web server
- Configure stub_status module for metrics
- Create systemd service
- Set up firewall rules
- Verify installation

### 2. Install NGINX Prometheus Exporter

```bash
chmod +x install_nginx_exporter.sh
sudo ./install_nginx_exporter.sh
```

This will:
- Download and install NGINX Prometheus exporter
- Create systemd service for the exporter
- Configure metrics endpoint
- Verify installation

### 3. Install Python Dependencies

```bash
pip3 install -r requirements.txt
```

### 4. Configure Azure Environment

**Option A: Using .env file (Recommended for testing)**

```bash
# Copy the example configuration
cp .env.example .env

# Edit with your values
nano .env
```

Example `.env` file:
```bash
AZURE_SUBSCRIPTION_ID=your-subscription-id-here
AZURE_RESOURCE_GROUP=your-resource-group-name
AZURE_RESOURCE_NAME=your-vm-name
AZURE_REGION=northeurope
```

**Option B: Using environment variables**

```bash
export AZURE_SUBSCRIPTION_ID="your-subscription-id"
export AZURE_RESOURCE_GROUP="your-resource-group"
export AZURE_RESOURCE_NAME="your-vm-name"
export AZURE_REGION="northeurope"  # Optional, defaults to northeurope
```

**Get these values:**
```bash
# Login to Azure CLI
az login

# Get subscription ID
az account show --query id -o tsv

# Get resource group and VM name
az vm list --query "[].{Name:name, ResourceGroup:resourceGroup}" -o table
```

### 5. Test the Setup

**Test Azure Monitor Connection:**

```bash
# Test configuration
python azure_monitor_sender.py --config-check

# Test Azure authentication
python azure_monitor_sender.py --health-check

# Send test metrics
python azure_monitor_sender.py --send-test

# Send custom test metric
python azure_monitor_sender.py --custom-metric "my_test_metric" 42.5
```

**Test Full NGINX Monitoring:**

```bash
# Health check
python3 nginx_metrics_monitor.py --health-check

# Single run test
python3 nginx_metrics_monitor.py --once

# Start monitoring (30-second intervals)
python3 nginx_metrics_monitor.py --interval 30
```

### 6. Production Deployment

```bash
chmod +x systemd_service.sh
sudo ./systemd_service.sh

# Edit configuration
sudo nano /etc/default/nginx-metrics-monitor

# Start service
sudo systemctl start nginx-metrics-monitor
sudo systemctl status nginx-metrics-monitor
```

## 📊 Metrics Collected

The following NGINX metrics are collected and sent to Azure Monitor:

| Metric Name | Description | Type |
|-------------|-------------|------|
| `nginx_connections_active` | Active connections | Gauge |
| `nginx_connections_reading` | Connections reading requests | Gauge |
| `nginx_connections_writing` | Connections writing responses | Gauge |
| `nginx_connections_waiting` | Idle connections waiting for requests | Gauge |
| `nginx_http_requests_total` | Total HTTP requests processed | Counter |
| `nginx_connections_accepted_total` | Total connections accepted | Counter |
| `nginx_connections_handled_total` | Total connections handled | Counter |
| `nginx_requests_per_second` | Request rate (calculated) | Gauge |

## 🔧 Configuration Options

### Command Line Arguments

**NGINX Metrics Monitor:**
```bash
python3 nginx_metrics_monitor.py [OPTIONS]

Options:
  --prometheus-url URL    Prometheus endpoint (default: http://localhost:9113/metrics)
  --interval SECONDS      Scrape interval (default: 60)
  --once                  Run once instead of continuous monitoring
  --managed-identity      Use Azure Managed Identity
  --health-check          Perform health check only
  --verbose               Enable debug logging
```

**Azure Monitor Sender Test Tool:**
```bash
python azure_monitor_sender.py [OPTIONS]

Options:
  --config-check          Check configuration only
  --health-check          Test connection health only
  --send-test            Send sample NGINX metrics
  --custom-metric NAME VALUE  Send a custom metric
  --namespace NS         Custom metrics namespace (default: Custom/Test)
  --env-file FILE        Path to .env file (default: .env)

Examples:
  python azure_monitor_sender.py --config-check
  python azure_monitor_sender.py --custom-metric "cpu_usage" 75.5
  python azure_monitor_sender.py --env-file production.env --health-check
```

### Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID | Yes |
| `AZURE_RESOURCE_GROUP` | Resource group name | Yes |
| `AZURE_RESOURCE_NAME` | VM/resource name | Yes |
| `AZURE_REGION` | Azure region for metrics endpoint | No (default: northeurope) |

## 🏥 Monitoring and Troubleshooting

### Service Status

```bash
# Check service status
sudo systemctl status nginx-metrics-monitor

# View logs
sudo journalctl -u nginx-metrics-monitor -f

# Or view log files directly
tail -f nginx_metrics_monitor.log
tail -f azure_monitor_sender.log

# Check NGINX exporter
curl http://localhost:9113/metrics
```

### Log Files

- Main service: `nginx_metrics_monitor.log` (in script directory)
- Azure sender: `azure_monitor_sender.log` (in script directory)
- Prometheus scraper: `prometheus_scraper.log` (in script directory)

### Testing and Debugging

**Step-by-step testing:**

```bash
# 1. Check if .env file is loaded correctly
python azure_monitor_sender.py --config-check

# 2. Test Azure authentication
python azure_monitor_sender.py --health-check

# 3. Send a test metric
python azure_monitor_sender.py --custom-metric "test_connection" 1.0

# 4. Test full NGINX monitoring
python nginx_metrics_monitor.py --health-check
```

### Common Issues

1. **Configuration missing**: Use `--config-check` to verify all variables are set
2. **Prometheus endpoint not accessible**: Check if NGINX exporter is running (`curl http://localhost:9113/metrics`)
3. **Azure authentication failed**:
   - Verify Azure credentials: `az login` and `az account show`
   - Check RBAC permissions on the VM resource
4. **No metrics in Azure Monitor**:
   - Check Azure resource configuration and permissions
   - Ensure VM has **Monitoring Contributor** role
5. **403 Forbidden errors**: Ensure VM has proper Azure RBAC permissions for custom metrics
6. **.env file not loading**: Ensure `.env` file is in the same directory as the script

## 🔒 Security

- Service runs under dedicated user account
- Uses Azure Managed Identity when available
- Logs sensitive information is filtered out
- Network access limited to required endpoints

## 🔄 Azure Monitor Integration

The metrics are sent to Azure Monitor Custom Metrics where they can be:

1. **Native Metrics**: View in Azure Monitor Metrics explorer
2. **Used for Autoscaling**: Create autoscale rules based on custom metrics
3. **Alerting**: Set up metric alerts based on thresholds
4. **Dashboards**: Create Azure dashboards with the metrics
5. **API Access**: Query via Azure Monitor REST API

### View Metrics in Azure Portal

1. Go to your VM in Azure Portal
2. Navigate to **Monitoring > Metrics**
3. Select **Custom** metrics namespace
4. Choose **Custom/NGINX** namespace
5. Select your NGINX metrics (e.g., `nginx_connections_active`)

### Example REST API Query

```bash
# Get metrics via REST API
curl -H "Authorization: Bearer $TOKEN" \
  "https://management.azure.com/subscriptions/{subscription}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachines/{vm}/providers/microsoft.insights/metrics?metricnames=nginx_connections_active&api-version=2018-01-01"
```

## 📈 Autoscaling Setup

Use the collected metrics for VM Scale Set autoscaling:

1. **Create Autoscale Rules**: In Azure portal, go to your VM Scale Set
2. **Add Custom Metric Rule**: Select **Custom** metrics
3. **Choose Metric**: Use `nginx_connections_active` or `nginx_requests_per_second`
4. **Set Thresholds**: Configure scale-out (>100 connections) and scale-in (<20 connections)
5. **Configure Actions**: Set instance count changes and cooldown periods

### Required Permissions

Ensure your VM/Scale Set has these permissions:
- **Monitoring Contributor** role on the resource
- Or custom role with `microsoft.insights/metrics/write` permission

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is provided as-is for educational and production use.