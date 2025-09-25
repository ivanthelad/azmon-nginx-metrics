#!/usr/bin/env python3

import requests
import time
from typing import Dict, Any, Optional
from prometheus_client.parser import text_string_to_metric_families
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('prometheus_scraper.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class PrometheusMetricsScraper:
    """Scraper for NGINX Prometheus metrics"""

    def __init__(self, prometheus_url: str = "http://localhost:9113/metrics"):
        self.prometheus_url = prometheus_url
        self.session = requests.Session()
        self.session.timeout = 10

    def scrape_metrics(self) -> Dict[str, Any]:
        """Scrape metrics from Prometheus endpoint"""
        try:
            response = self.session.get(self.prometheus_url)
            response.raise_for_status()

            metrics = {}

            # Parse Prometheus metrics format
            for family in text_string_to_metric_families(response.text):
                for sample in family.samples:
                    metric_name = sample.name
                    metric_value = sample.value
                    labels = sample.labels

                    # Store metric with labels as context
                    metrics[metric_name] = {
                        'value': metric_value,
                        'labels': labels,
                        'timestamp': time.time()
                    }

            logger.info(f"Successfully scraped {len(metrics)} metrics")
            return metrics

        except requests.RequestException as e:
            logger.error(f"Failed to scrape metrics: {e}")
            return {}
        except Exception as e:
            logger.error(f"Unexpected error scraping metrics: {e}")
            return {}

    def get_nginx_key_metrics(self) -> Dict[str, float]:
        """Extract all NGINX metrics for Azure Monitor"""
        all_metrics = self.scrape_metrics()

        if not all_metrics:
            logger.warning("No metrics available to extract")
            return {}

        # Convert all numeric metrics to float values
        key_metrics = {}

        for metric_name, metric_data in all_metrics.items():
            try:
                # Extract numeric value from metric
                value = float(metric_data['value'])

                # Skip metrics with labels for now (they need special handling)
                labels = metric_data.get('labels', {})
                if not labels:  # Only process metrics without labels
                    key_metrics[metric_name] = value
                else:
                    # For labeled metrics, create a simplified name
                    label_suffix = "_".join([f"{k}_{v}" for k, v in labels.items()])
                    simplified_name = f"{metric_name}_{label_suffix}"
                    key_metrics[simplified_name] = value

            except (ValueError, TypeError) as e:
                logger.debug(f"Skipping non-numeric metric {metric_name}: {e}")
                continue

        # Calculate request rate (requests per second)
        current_requests = key_metrics.get('nginx_http_requests_total', 0)
        if hasattr(self, '_last_requests') and hasattr(self, '_last_timestamp'):
            current_time = time.time()
            time_diff = current_time - self._last_timestamp

            if time_diff > 0:
                requests_per_second = (current_requests - self._last_requests) / time_diff
                key_metrics['nginx_requests_per_second'] = max(0.0, requests_per_second)  # Ensure non-negative

        # Store for next calculation
        self._last_requests = current_requests
        self._last_timestamp = time.time()

        logger.info(f"Extracted {len(key_metrics)} metrics from Prometheus")
        logger.debug(f"All metrics: {list(key_metrics.keys())}")
        return key_metrics

    def health_check(self) -> bool:
        """Check if Prometheus endpoint is healthy"""
        try:
            response = self.session.get(self.prometheus_url, timeout=5)
            return response.status_code == 200
        except Exception:
            return False


if __name__ == "__main__":
    scraper = PrometheusMetricsScraper()

    # Test the scraper
    if scraper.health_check():
        print("✅ Prometheus endpoint is accessible")
        metrics = scraper.get_nginx_key_metrics()
        print("Key metrics:")
        for metric, value in metrics.items():
            print(f"  {metric}: {value}")
    else:
        print("❌ Cannot access Prometheus endpoint")
        print("Make sure NGINX Prometheus exporter is running on http://localhost:9113/metrics")