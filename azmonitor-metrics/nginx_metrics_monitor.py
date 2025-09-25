#!/usr/bin/env python3

import os
import sys
import time
import signal
import logging
import argparse
from typing import Dict, Optional
from pathlib import Path

# Add current directory to path for imports
sys.path.append(str(Path(__file__).parent))

from prometheus_scraper import PrometheusMetricsScraper
from azure_monitor_sender import AzureMonitorSender, get_azure_config

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('nginx_metrics_monitor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class NginxMetricsMonitor:
    """Main orchestrator for NGINX metrics monitoring and Azure Monitor integration"""

    def __init__(self,
                 prometheus_url: str = "http://localhost:9113/metrics",
                 scrape_interval: int = 60,
                 use_managed_identity: bool = False):

        self.scrape_interval = scrape_interval
        self.running = False

        # Initialize components
        self.scraper = PrometheusMetricsScraper(prometheus_url)

        azure_config = get_azure_config()
        self.azure_sender = AzureMonitorSender(
            subscription_id=azure_config['subscription_id'],
            resource_group=azure_config['resource_group'],
            resource_name=azure_config['resource_name'],
            use_managed_identity=use_managed_identity
        )

        # Setup signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals"""
        logger.info(f"Received signal {signum}, shutting down gracefully...")
        self.running = False

    def health_check(self) -> bool:
        """Perform health check on all components"""
        logger.info("Performing health checks...")

        prometheus_healthy = self.scraper.health_check()
        logger.info(f"Prometheus endpoint: {'✅' if prometheus_healthy else '❌'}")

        azure_healthy = self.azure_sender.health_check()
        logger.info(f"Azure Monitor: {'✅' if azure_healthy else '❌'}")

        return prometheus_healthy and azure_healthy

    def collect_and_send_metrics(self) -> bool:
        """Collect metrics from Prometheus and send to Azure Monitor"""
        try:
            # Scrape metrics from Prometheus
            logger.debug("Scraping metrics from Prometheus...")
            metrics = self.scraper.get_nginx_key_metrics()

            if not metrics:
                logger.warning("No metrics collected from Prometheus")
                return False

            # Send to Azure Monitor Custom Metrics
            logger.debug("Sending metrics to Azure Monitor Custom Metrics...")
            success = self.azure_sender.send_metrics(
                metrics=metrics,
                namespace="Custom/NGINX"
            )

            if success:
                logger.info(f"Successfully processed {len(metrics)} metrics")

                # Log key metrics for visibility
                key_metrics = {
                    'active_connections': metrics.get('nginx_connections_active', 0),
                    'total_requests': metrics.get('nginx_http_requests_total', 0),
                    'requests_per_second': metrics.get('nginx_requests_per_second', 0)
                }
                logger.info(f"Key metrics: {key_metrics}")
            else:
                logger.error("Failed to send metrics to Azure Monitor")

            return success

        except Exception as e:
            logger.error(f"Error in collect_and_send_metrics: {e}")
            return False

    def run(self) -> None:
        """Main monitoring loop"""
        logger.info(f"Starting NGINX Metrics Monitor (interval: {self.scrape_interval}s)")

        # Initial health check
        if not self.health_check():
            logger.error("Health check failed. Check configuration and dependencies.")
            sys.exit(1)

        self.running = True
        consecutive_failures = 0
        max_consecutive_failures = 5

        while self.running:
            try:
                success = self.collect_and_send_metrics()

                if success:
                    consecutive_failures = 0
                else:
                    consecutive_failures += 1
                    logger.warning(f"Consecutive failures: {consecutive_failures}")

                    if consecutive_failures >= max_consecutive_failures:
                        logger.error(f"Max consecutive failures ({max_consecutive_failures}) reached. Stopping.")
                        break

                # Wait for next interval
                for _ in range(self.scrape_interval):
                    if not self.running:
                        break
                    time.sleep(1)

            except KeyboardInterrupt:
                logger.info("Received keyboard interrupt")
                break
            except Exception as e:
                logger.error(f"Unexpected error in main loop: {e}")
                consecutive_failures += 1
                time.sleep(10)  # Wait before retrying

        logger.info("NGINX Metrics Monitor stopped")

    def run_once(self) -> bool:
        """Run metrics collection once (useful for testing or cron jobs)"""
        logger.info("Running single metrics collection...")

        if not self.health_check():
            logger.error("Health check failed")
            return False

        return self.collect_and_send_metrics()


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='NGINX Metrics Monitor for Azure')

    parser.add_argument(
        '--prometheus-url',
        default='http://localhost:9113/metrics',
        help='Prometheus metrics endpoint URL'
    )

    parser.add_argument(
        '--interval',
        type=int,
        default=60,
        help='Scrape interval in seconds (default: 60)'
    )

    parser.add_argument(
        '--once',
        action='store_true',
        help='Run once instead of continuous monitoring'
    )

    parser.add_argument(
        '--managed-identity',
        action='store_true',
        help='Use Azure Managed Identity for authentication'
    )

    parser.add_argument(
        '--health-check',
        action='store_true',
        help='Perform health check only and exit'
    )

    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable debug logging'
    )

    args = parser.parse_args()

    # Set logging level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Initialize monitor
    monitor = NginxMetricsMonitor(
        prometheus_url=args.prometheus_url,
        scrape_interval=args.interval,
        use_managed_identity=args.managed_identity
    )

    # Handle different run modes
    if args.health_check:
        healthy = monitor.health_check()
        sys.exit(0 if healthy else 1)
    elif args.once:
        success = monitor.run_once()
        sys.exit(0 if success else 1)
    else:
        monitor.run()


if __name__ == "__main__":
    main()