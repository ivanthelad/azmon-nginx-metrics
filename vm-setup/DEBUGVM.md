# Debugging Cloud-Init VM Deployment

Guide for troubleshooting Azure VM deployment and cloud-init issues.

## 1. SSH to the VM

```bash
# Use the public IP from the deployment output
ssh azureuser@<vm-public-ip>

# Or request JIT access if needed
az security jit-policy upsert --resource-group <rg> --name <vm>-jit-policy --virtual-machines '[{"id":"/subscriptions/.../resourceGroups/<rg>/providers/Microsoft.Compute/virtualMachines/<vm>","ports":[{"number":22,"protocol":"*","allowedSourceAddressPrefix":"*","maxRequestAccessDuration":"PT3H"}]}]'
```

## 2. Check Cloud-Init Status

```bash
# Check if cloud-init is still running
sudo cloud-init status

# Get detailed status
sudo cloud-init status --long

# Check if cloud-init completed successfully
sudo cloud-init status --wait
```

## 3. View Cloud-Init Logs

```bash
# Main cloud-init log
sudo cat /var/log/cloud-init.log

# Output from scripts/commands
sudo cat /var/log/cloud-init-output.log

# Follow logs in real-time
sudo tail -f /var/log/cloud-init-output.log

# System journal for cloud-init
sudo journalctl -u cloud-init -f
```

## 4. Check Specific Service Status

```bash
# Check if nginx-monitor service is running
sudo systemctl status nginx-monitor.service

# View service logs
sudo journalctl -u nginx-monitor.service -f

# Check Docker services
docker-compose -f /opt/nginx-monitor/docker-compose.yml ps
docker-compose -f /opt/nginx-monitor/docker-compose.yml logs
```

## 5. Validate Cloud-Init Configuration

```bash
# Check the processed cloud-init config
sudo cloud-init query all

# Validate cloud-init syntax
sudo cloud-init schema --system

# View the original cloud-init data
sudo cat /var/lib/cloud/instance/user-data.txt
```

## 6. Debug Network and Container Issues

```bash
# Check if containers are running
docker ps -a

# Check container logs
docker logs nginx-server
docker logs nginx-prometheus-exporter
docker logs metrics-collector

# Test endpoints locally
curl http://localhost/health
curl http://localhost:9113/metrics
```

## 7. Re-run Cloud-Init (if needed)

```bash
# Clean and re-run cloud-init (use with caution)
sudo cloud-init clean
sudo cloud-init init --local
sudo cloud-init init
sudo cloud-init modules --mode=config
sudo cloud-init modules --mode=final
```

## 8. Common Issues to Check

```bash
# Check disk space
df -h

# Check if Docker is running
sudo systemctl status docker

# Check if required ports are open
sudo netstat -tlnp | grep -E ':(80|9113|8000)'

# Check Azure managed identity
curl -H "Metadata:true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com/"
```

## 9. Debug from Azure Portal

- Go to VM → **Boot diagnostics** → **Serial log** to see early boot messages
- Check VM → **Activity log** for deployment events
- View VM → **Run command** to execute commands without SSH

## 10. Check Cloud-Init Module Status

```bash
# See which modules ran and their status
sudo cat /var/lib/cloud/data/result.json

# Check module-specific logs
sudo cat /var/lib/cloud/instance/scripts/part-001
```

## Most Common Issues

The most common issues are usually visible in:
- `/var/log/cloud-init-output.log` - Script execution output
- `sudo systemctl status nginx-monitor.service` - Service status
- `docker-compose logs` - Container issues