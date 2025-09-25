import requests
import time
from azure.identity import DefaultAzureCredential
from azure.monitor.opentelemetry.exporter import AzureMonitorMetricExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry import metrics

# Setup Azure Monitor exporter
credential = DefaultAzureCredential()
exporter = AzureMonitorMetricExporter(credential=credential)

reader = PeriodicExportingMetricReader(exporter)
provider = MeterProvider(metric_readers=[reader])
metrics.set_meter_provider(provider)
meter = metrics.get_meter("nginx.metrics")

# Define metrics
reqs_metric = meter.create_up_down_counter(
    name="nginx_requests_total",
    unit="1",
    description="Total requests handled by NGINX"
)
conns_metric = meter.create_up_down_counter(
    name="nginx_active_connections",
    unit="1",
    description="Active connections in NGINX"
)

def get_nginx_metrics():
    response = requests.get("http://localhost/nginx_status")
    data = response.text
    lines = data.strip().split("\n")
    
    active_connections = int(lines[0].split(":")[1].strip())
    requests_line = lines[2].split()
    total_requests = int(requests_line[2])

    return active_connections, total_requests

# Periodically push metrics
while True:
    active, total = get_nginx_metrics()
    print(f"Pushing metrics: Active={active}, Total Requests={total}")

    conns_metric.add(active, {"source": "nginx"})
    reqs_metric.add(total, {"source": "nginx"})

    time.sleep(60)  # send every 60 seconds
