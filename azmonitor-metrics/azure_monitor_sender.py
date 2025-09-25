#!/usr/bin/env python3

import os
import sys
import time
import logging
import requests
import json
from typing import Dict, List, Optional
from datetime import datetime, timezone
from pathlib import Path

from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
from azure.core.exceptions import AzureError

# Load environment variables from .env file if it exists
def load_env_file(env_file_path: str = '.env'):
    """Load environment variables from .env file"""
    env_path = Path(env_file_path)

    if env_path.exists():
        print(f"📄 Loading environment from {env_path}")
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    # Remove quotes if present
                    value = value.strip('"').strip("'")
                    os.environ[key] = value
        print(f"✅ Environment loaded from {env_path}")
    else:
        print(f"ℹ️  No .env file found at {env_path}")

# Load .env file at module level
load_env_file()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('azure_monitor_sender.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class AzureMonitorSender:
    """Send custom metrics to Azure Monitor using REST API"""

    def __init__(self,
                 subscription_id: Optional[str] = None,
                 resource_group: Optional[str] = None,
                 resource_name: Optional[str] = None,
                 use_managed_identity: Optional[bool] = None):

        # Auto-detect authentication method if not specified
        if use_managed_identity is None:
            use_managed_identity = self._should_use_managed_identity()

        # Authentication
        if use_managed_identity:
            logger.info("🔑 Using Managed Identity for Azure authentication")
            self.credential = ManagedIdentityCredential()
        else:
            logger.info("🔑 Using DefaultAzureCredential for Azure authentication")
            self.credential = DefaultAzureCredential(exclude_environment_credential=True)

        # Try to get resource information from IMDS first, then fall back to environment/parameters
        try:
            imds_info = self._get_imds_metadata()
            self.subscription_id = subscription_id or os.getenv('AZURE_SUBSCRIPTION_ID') or imds_info.get('subscriptionId')
            self.resource_group = resource_group or os.getenv('AZURE_RESOURCE_GROUP') or imds_info.get('resourceGroupName')
            self.resource_name = resource_name or os.getenv('AZURE_RESOURCE_NAME') or imds_info.get('name')
            self.location = imds_info.get('location') or os.getenv('AZURE_REGION', 'northeurope')

            # Store VMSS-specific information
            self.is_vmss = imds_info.get('isVmss', False)
            self.vmss_name = imds_info.get('vmScaleSetName')
            self.instance_id = imds_info.get('instanceId')

            if self.is_vmss:
                logger.info("✅ Successfully retrieved VMSS metadata from Azure IMDS")
                logger.info(f"📊 Auto-detected VMSS: {self.vmss_name} - Instance: {self.instance_id} in {self.resource_group} ({self.subscription_id})")
            else:
                logger.info("✅ Successfully retrieved VM metadata from Azure IMDS")
                logger.info(f"📊 Auto-detected VM: {self.resource_name} in {self.resource_group} ({self.subscription_id})")

        except Exception as e:
            logger.warning(f"Failed to get IMDS metadata, using environment variables: {e}")
            # Fallback to manual configuration
            self.subscription_id = subscription_id or os.getenv('AZURE_SUBSCRIPTION_ID')
            self.resource_group = resource_group or os.getenv('AZURE_RESOURCE_GROUP')
            self.resource_name = resource_name or os.getenv('AZURE_RESOURCE_NAME')
            self.location = os.getenv('AZURE_REGION', 'northeurope')
            self.is_vmss = False
            self.vmss_name = None
            self.instance_id = None

        # Build resource URI based on resource type
        if all([self.subscription_id, self.resource_group]):
            if self.is_vmss and self.vmss_name:
                # VMSS resource URI format (send metrics to VMSS, not individual instances)
                self.resource_uri = f"/subscriptions/{self.subscription_id}/resourceGroups/{self.resource_group}/providers/Microsoft.Compute/virtualMachineScaleSets/{self.vmss_name}"
                logger.info(f"📊 Configured Azure Monitor for VMSS: {self.vmss_name} (instance: {self.instance_id}) in {self.resource_group}")
            elif self.resource_name:
                # Standalone VM resource URI format
                self.resource_uri = f"/subscriptions/{self.subscription_id}/resourceGroups/{self.resource_group}/providers/Microsoft.Compute/virtualMachines/{self.resource_name}"
                logger.info(f"📊 Configured Azure Monitor for VM: {self.resource_name} in {self.resource_group}")
            else:
                logger.warning("Missing resource name for Azure configuration.")
                self.resource_uri = None

            if self.resource_uri:
                self.metrics_endpoint = f"https://{self.location}.monitoring.azure.com{self.resource_uri}/metrics"
                logger.info(f"🎯 Resource URI: {self.resource_uri}")
            else:
                self.metrics_endpoint = None
        else:
            logger.warning("Missing Azure configuration. Metrics endpoint not initialized.")
            logger.warning(f"Available values: subscription_id={self.subscription_id}, resource_group={self.resource_group}, resource_name={self.resource_name}")
            self.resource_uri = None
            self.metrics_endpoint = None

    def _get_imds_metadata(self) -> Dict[str, str]:
        """Get VM or VMSS metadata from Azure Instance Metadata Service (IMDS)"""
        try:
            # Azure IMDS endpoint for compute metadata
            imds_url = "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01"
            headers = {'Metadata': 'true'}

            response = requests.get(imds_url, headers=headers, timeout=5)
            response.raise_for_status()

            metadata = response.json()

            # Detect if running on VMSS or standalone VM
            is_vmss = 'vmScaleSetName' in metadata and metadata.get('vmScaleSetName')

            # Extract relevant information
            result = {
                'subscriptionId': metadata.get('subscriptionId'),
                'resourceGroupName': metadata.get('resourceGroupName'),
                'name': metadata.get('name'),
                'location': metadata.get('location'),
                'vmId': metadata.get('vmId'),
                'resourceId': metadata.get('resourceId'),
                'isVmss': is_vmss
            }

            # Add VMSS-specific metadata if applicable
            if is_vmss:
                result.update({
                    'vmScaleSetName': metadata.get('vmScaleSetName'),
                    'instanceId': metadata.get('name')  # For VMSS, 'name' is the instance name/ID
                })
                logger.info(f"🔍 Detected VMSS instance: {metadata.get('vmScaleSetName')} - Instance: {metadata.get('name')}")
            else:
                logger.info(f"🔍 Detected standalone VM: {metadata.get('name')}")

            logger.debug(f"IMDS metadata retrieved: {result}")
            return result

        except requests.RequestException as e:
            logger.debug(f"IMDS request failed: {e}")
            raise Exception(f"Unable to reach Azure IMDS: {e}")
        except (KeyError, ValueError) as e:
            logger.debug(f"IMDS response parsing failed: {e}")
            raise Exception(f"Invalid IMDS response: {e}")

    def _should_use_managed_identity(self) -> bool:
        """Auto-detect if we should use managed identity"""
        # Check if explicitly requested via environment variable
        use_managed = os.getenv('AZURE_USE_MANAGED_IDENTITY', '').lower()
        if use_managed in ['true', '1', 'yes']:
            return True

        # Check if we're likely running on Azure (has IMDS endpoint available)
        try:
            response = requests.get(
                'http://169.254.169.254/metadata/instance',
                headers={'Metadata': 'true'},
                timeout=2
            )
            if response.status_code == 200:
                logger.info("🔍 Detected Azure environment - IMDS endpoint available")
                return True
        except:
            pass

        # Check if service principal credentials are missing/invalid
        client_id = os.getenv('AZURE_CLIENT_ID', '')
        client_secret = os.getenv('AZURE_CLIENT_SECRET', '')
        tenant_id = os.getenv('AZURE_TENANT_ID', '')

        # If any credential is missing or looks like a placeholder, use managed identity
        placeholder_values = ['your-client-id', 'your-client-secret', 'your-tenant-id', '']
        if (client_id in placeholder_values or
            client_secret in placeholder_values or
            tenant_id in placeholder_values):
            logger.info("🔍 Service principal credentials missing or placeholder - using managed identity")
            return True

        logger.info("🔍 Valid service principal credentials found - using DefaultAzureCredential")
        return False

    def send_metrics(self, metrics: Dict[str, float],
                    namespace: str = "Custom/NGINX") -> bool:
        """Send custom metrics to Azure Monitor using REST API"""

        if not self.resource_uri:
            logger.error("Azure Monitor not properly configured - missing resource URI")
            return False

        try:
            # Get access token for Azure Monitor Custom Metrics
            token = self.credential.get_token("https://monitoring.azure.com/.default")
            headers = {
                "Authorization": f"Bearer {token.token}",
                "Content-Type": "application/json"
            }

            timestamp = datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z')

            # Send each metric individually
            success_count = 0
            for metric_name, metric_value in metrics.items():
                # Build payload for each metric according to Azure Monitor custom metrics API
                payload = {
                    "time": timestamp,
                    "data": {
                        "baseData": {
                            "metric": metric_name,
                            "namespace": namespace,
                            "dimNames": ["VMName"] if self.is_vmss and self.instance_id else [],
                            "series": [{
                                "dimValues": [f"{self.vmss_name}_{self.instance_id}"] if self.is_vmss and self.instance_id else [],
                                "min": float(metric_value),
                                "max": float(metric_value),
                                "sum": float(metric_value),
                                "count": 1
                            }]
                        }
                    }
                }

                # Use the correct Azure Monitor custom metrics endpoint
                # Format: https://{region}.monitoring.azure.com{resourceId}/metrics
                region = self.location or 'northeurope'
                endpoint = f"https://{region}.monitoring.azure.com{self.resource_uri}/metrics"

                logger.info(f"🌐 Sending metric '{metric_name}' (value: {metric_value}) to Azure Monitor")
                logger.info(f"🎯 Endpoint: {endpoint}")
                logger.info(f"📦 Namespace: {namespace}")

                response = requests.post(
                    endpoint,
                    headers=headers,
                    json=payload,
                    timeout=30
                )

                if response.status_code in [200, 202, 204]:
                    success_count += 1
                    logger.debug(f"Successfully sent metric {metric_name}")
                else:
                    logger.error(f"Failed to send metric {metric_name}. Status: {response.status_code}, Response: {response.text}")

            if success_count > 0:
                logger.info(f"Successfully sent {success_count}/{len(metrics)} custom metrics to Azure Monitor")
                return success_count == len(metrics)
            else:
                return False

        except Exception as e:
            logger.error(f"Error sending custom metrics: {e}")
            return False


    def health_check(self) -> bool:
        """Check if Azure Monitor connection is healthy"""
        if not self.resource_uri:
            logger.error("Azure Monitor configuration incomplete")
            return False

        try:
            # Try to authenticate with Azure Monitor Custom Metrics
            token = self.credential.get_token("https://monitoring.azure.com/.default")
            if token and token.token:
                logger.info("Azure Monitor authentication successful")
                return True
            else:
                logger.error("Failed to get Azure Monitor access token")
                return False
        except Exception as e:
            logger.error(f"Azure Monitor health check failed: {e}")
            return False


# Configuration helper
def get_azure_config() -> Dict[str, str]:
    """Get Azure configuration from IMDS or environment for Custom Metrics (supports VM and VMSS)"""
    config = {
        'subscription_id': os.getenv('AZURE_SUBSCRIPTION_ID'),
        'resource_group': os.getenv('AZURE_RESOURCE_GROUP'),
        'resource_name': os.getenv('AZURE_RESOURCE_NAME'),
        'region': os.getenv('AZURE_REGION', 'northeurope'),
        'is_vmss': False,
        'vmss_name': None,
        'instance_id': None
    }

    # Try to get missing values from IMDS
    try:
        imds_url = "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01"
        headers = {'Metadata': 'true'}
        response = requests.get(imds_url, headers=headers, timeout=5)
        response.raise_for_status()
        metadata = response.json()

        # Detect if running on VMSS
        is_vmss = 'vmScaleSetName' in metadata and metadata.get('vmScaleSetName')

        # Fill in missing values from IMDS
        if not config['subscription_id']:
            config['subscription_id'] = metadata.get('subscriptionId')
        if not config['resource_group']:
            config['resource_group'] = metadata.get('resourceGroupName')
        if not config['resource_name']:
            config['resource_name'] = metadata.get('name')
        if not config['region']:
            config['region'] = metadata.get('location', 'northeurope')

        # Add VMSS-specific configuration
        config['is_vmss'] = is_vmss
        if is_vmss:
            config['vmss_name'] = metadata.get('vmScaleSetName')
            config['instance_id'] = metadata.get('name')
            logger.info(f"✅ Enhanced configuration with VMSS IMDS metadata: {config['vmss_name']}/{config['instance_id']}")
        else:
            logger.info("✅ Enhanced configuration with VM IMDS metadata")

    except Exception as e:
        logger.debug(f"Could not retrieve IMDS metadata for config: {e}")

    missing_keys = [k for k, v in config.items() if not v and k not in ['region', 'is_vmss', 'vmss_name', 'instance_id']]
    if missing_keys:
        logger.warning(f"Missing Azure configuration: {missing_keys}")

    return config


def test_health_check():
    """Test Azure Monitor connection health"""
    config = get_azure_config()
    sender = AzureMonitorSender(
        subscription_id=config['subscription_id'],
        resource_group=config['resource_group'],
        resource_name=config['resource_name']
    )

    print("🔍 Testing Azure Monitor connection...")
    healthy = sender.health_check()
    print(f"Health check: {'✅ Healthy' if healthy else '❌ Failed'}")
    return healthy

def test_send_metrics():
    """Test sending sample metrics to Azure Monitor"""
    config = get_azure_config()
    sender = AzureMonitorSender(
        subscription_id=config['subscription_id'],
        resource_group=config['resource_group'],
        resource_name=config['resource_name']
    )

    # Test metrics
    test_metrics = {
        'nginx_connections_active': 10.0,
        'nginx_http_requests_total': 1000.0,
        'nginx_requests_per_second': 5.5
    }

    print("📊 Sending test metrics...")
    success = sender.send_metrics(test_metrics, namespace="Custom/NGINX")
    print(f"Send metrics: {'✅ Success' if success else '❌ Failed'}")
    return success

def test_custom_metrics(metrics: dict, namespace: str = "Custom/Test"):
    """Test sending custom metrics"""
    config = get_azure_config()
    sender = AzureMonitorSender(
        subscription_id=config['subscription_id'],
        resource_group=config['resource_group'],
        resource_name=config['resource_name']
    )

    print(f"📊 Sending custom metrics to namespace '{namespace}'...")
    success = sender.send_metrics(metrics, namespace=namespace)
    print(f"Custom metrics: {'✅ Success' if success else '❌ Failed'}")
    return success

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description='Azure Monitor Sender Test Tool')
    parser.add_argument('--health-check', action='store_true',
                       help='Test connection health only')
    parser.add_argument('--send-test', action='store_true',
                       help='Send sample NGINX metrics')
    parser.add_argument('--config-check', action='store_true',
                       help='Check configuration only')
    parser.add_argument('--custom-metric', nargs=2, metavar=('NAME', 'VALUE'),
                       help='Send a custom metric: --custom-metric metric_name 42.5')
    parser.add_argument('--namespace', default='Custom/Test',
                       help='Custom metrics namespace (default: Custom/Test)')
    parser.add_argument('--env-file', default='.env',
                       help='Path to .env file (default: .env)')

    args = parser.parse_args()

    # Load custom .env file if specified
    if args.env_file != '.env':
        load_env_file(args.env_file)

    # Configuration check
    if args.config_check:
        print("🔧 Checking configuration...")
        config = get_azure_config()
        print("Configuration:")
        for key, value in config.items():
            status = "✅" if value else "❌"
            print(f"  {status} {key}: {value if value else 'MISSING'}")
        exit(0)

    # Health check only
    if args.health_check:
        healthy = test_health_check()
        exit(0 if healthy else 1)

    # Custom metric
    if args.custom_metric:
        metric_name, metric_value = args.custom_metric
        try:
            value = float(metric_value)
            success = test_custom_metrics({metric_name: value}, args.namespace)
            exit(0 if success else 1)
        except ValueError:
            print(f"❌ Invalid metric value: {metric_value} (must be a number)")
            exit(1)

    # Send test metrics (default behavior or --send-test)
    if args.send_test or len(sys.argv) == 1:
        print("🧪 Running full Azure Monitor sender test...")

        # Check configuration
        config = get_azure_config()
        missing = [k for k, v in config.items() if not v and k != 'region']
        if missing:
            print(f"❌ Missing configuration: {missing}")
            print("Set these environment variables:")
            for var in missing:
                print(f"  export AZURE_{var.upper()}='your-value'")
            exit(1)

        # Run tests
        health_ok = test_health_check()
        if health_ok:
            metrics_ok = test_send_metrics()
            if metrics_ok:
                print("\n🎉 All tests passed! Azure Monitor Custom Metrics is working.")
                exit(0)
            else:
                print("\n❌ Metrics sending failed.")
                exit(1)
        else:
            print("\n❌ Health check failed. Check Azure credentials and configuration.")
            exit(1)