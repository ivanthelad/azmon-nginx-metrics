#!/usr/bin/env python3

import os
import sys
import time
import logging
import requests
import json
from typing import Dict, Any, Optional
from urllib.parse import urljoin
import threading
from flask import Flask, Response
from prometheus_client import (
    Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST,
    CollectorRegistry, REGISTRY
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class NginxPrometheusExporter:
    """NGINX Prometheus exporter supporting stub_status and basic JSON metrics"""

    def __init__(self,
                 nginx_status_url: str = "http://nginx/nginx_status",
                 nginx_json_url: str = "http://nginx/status_json",
                 scrape_interval: int = 15):

        self.nginx_status_url = nginx_status_url
        self.nginx_json_url = nginx_json_url
        self.scrape_interval = scrape_interval
        self.session = requests.Session()
        self.session.timeout = 10

        # Create custom registry for this exporter
        self.registry = CollectorRegistry()

        # Basic NGINX metrics (from stub_status)
        self.nginx_connections_active = Gauge(
            'nginx_connections_active_total',
            'Active connections',
            registry=self.registry
        )
        self.nginx_connections_accepted = Counter(
            'nginx_connections_accepted_total',
            'Accepted connections',
            registry=self.registry
        )
        self.nginx_connections_handled = Counter(
            'nginx_connections_handled_total',
            'Handled connections',
            registry=self.registry
        )
        self.nginx_requests_total = Counter(
            'nginx_http_requests_total',
            'Total HTTP requests',
            registry=self.registry
        )
        self.nginx_connections_reading = Gauge(
            'nginx_connections_reading',
            'Connections reading',
            registry=self.registry
        )
        self.nginx_connections_writing = Gauge(
            'nginx_connections_writing',
            'Connections writing',
            registry=self.registry
        )
        self.nginx_connections_waiting = Gauge(
            'nginx_connections_waiting',
            'Connections waiting',
            registry=self.registry
        )

        # Basic status metrics from JSON endpoint
        self.nginx_status_info = Gauge(
            'nginx_status_info',
            'NGINX status information',
            ['server_name', 'nginx_version'],
            registry=self.registry
        )

        # Exporter health metrics
        self.exporter_scrapes_total = Counter(
            'nginx_exporter_scrapes_total',
            'Total scrapes by the exporter',
            ['result'],
            registry=self.registry
        )
        self.exporter_scrape_duration = Histogram(
            'nginx_exporter_scrape_duration_seconds',
            'Duration of scrapes by the exporter',
            registry=self.registry
        )

        # Start background scraper
        self._stop_event = threading.Event()
        self._scraper_thread = threading.Thread(target=self._scrape_loop, daemon=True)
        self._scraper_thread.start()

        logger.info(f"NGINX Prometheus Exporter initialized")
        logger.info(f"Basic metrics URL: {self.nginx_status_url}")
        logger.info(f"JSON status URL: {self.nginx_json_url}")
        logger.info(f"Scrape interval: {self.scrape_interval}s")

    def _scrape_loop(self):
        """Background scraping loop"""
        while not self._stop_event.is_set():
            start_time = time.time()

            try:
                # Scrape basic metrics
                basic_success = self._scrape_basic_metrics()

                # Scrape JSON status metrics
                json_success = self._scrape_json_metrics()

                # Record scrape result
                if basic_success or json_success:
                    self.exporter_scrapes_total.labels(result='success').inc()
                else:
                    self.exporter_scrapes_total.labels(result='failed').inc()

                # Record scrape duration
                duration = time.time() - start_time
                self.exporter_scrape_duration.observe(duration)

                logger.debug(f"Scrape completed in {duration:.3f}s (basic: {basic_success}, json: {json_success})")

            except Exception as e:
                self.exporter_scrapes_total.labels(result='error').inc()
                logger.error(f"Error in scrape loop: {e}")

            # Wait for next scrape
            self._stop_event.wait(self.scrape_interval)

    def _scrape_basic_metrics(self) -> bool:
        """Scrape basic NGINX stub_status metrics"""
        try:
            response = self.session.get(self.nginx_status_url)
            response.raise_for_status()

            lines = response.text.strip().split('\n')

            # Parse stub_status format:
            # Active connections: 1
            # server accepts handled requests
            #  16 16 31
            # Reading: 0 Writing: 1 Waiting: 0

            if len(lines) >= 3:
                # Active connections
                active_line = lines[0]
                if 'Active connections:' in active_line:
                    active = int(active_line.split(':')[1].strip())
                    self.nginx_connections_active.set(active)

                # Server stats
                stats_line = lines[2].strip().split()
                if len(stats_line) >= 3:
                    accepts = int(stats_line[0])
                    handled = int(stats_line[1])
                    requests = int(stats_line[2])

                    self.nginx_connections_accepted._value._value = accepts
                    self.nginx_connections_handled._value._value = handled
                    self.nginx_requests_total._value._value = requests

                # Reading/Writing/Waiting
                if len(lines) >= 4:
                    rw_line = lines[3]
                    parts = rw_line.split()
                    for i in range(0, len(parts), 2):
                        if i + 1 < len(parts):
                            metric_name = parts[i].rstrip(':').lower()
                            value = int(parts[i + 1])

                            if metric_name == 'reading':
                                self.nginx_connections_reading.set(value)
                            elif metric_name == 'writing':
                                self.nginx_connections_writing.set(value)
                            elif metric_name == 'waiting':
                                self.nginx_connections_waiting.set(value)

            logger.debug("Successfully scraped basic NGINX metrics")
            return True

        except Exception as e:
            logger.warning(f"Failed to scrape basic metrics: {e}")
            return False

    def _scrape_json_metrics(self) -> bool:
        """Scrape basic JSON status metrics"""
        try:
            response = self.session.get(self.nginx_json_url)
            response.raise_for_status()

            data = response.json()

            # Extract basic status information
            server_name = data.get('server_name', 'unknown')
            nginx_version = data.get('nginx_version', 'unknown')
            status = data.get('status', 'unknown')

            # Set status information metric
            if status == 'active':
                self.nginx_status_info.labels(
                    server_name=server_name,
                    nginx_version=nginx_version
                ).set(1)

            logger.debug("Successfully scraped JSON status metrics")
            return True

        except Exception as e:
            logger.debug(f"Failed to scrape JSON metrics: {e}")
            return False

    def get_metrics(self) -> str:
        """Get Prometheus formatted metrics"""
        return generate_latest(self.registry)

    def health_check(self) -> bool:
        """Health check for the exporter"""
        try:
            # Test basic connectivity
            basic_ok = requests.get(self.nginx_status_url, timeout=5).status_code == 200
            return basic_ok
        except:
            return False

    def stop(self):
        """Stop the exporter"""
        self._stop_event.set()
        self._scraper_thread.join(timeout=10)


# Flask app for serving metrics
app = Flask(__name__)
exporter = None

@app.route('/metrics')
def metrics():
    """Serve Prometheus metrics"""
    if exporter:
        return Response(exporter.get_metrics(), mimetype=CONTENT_TYPE_LATEST)
    else:
        return Response("Exporter not initialized", status=503)

@app.route('/health')
def health():
    """Health check endpoint"""
    if exporter and exporter.health_check():
        return "OK", 200
    else:
        return "Unhealthy", 503

@app.route('/')
def index():
    """Root endpoint with information"""
    return """
    <h1>NGINX Prometheus Exporter</h1>
    <ul>
        <li><a href="/metrics">Prometheus Metrics</a></li>
        <li><a href="/health">Health Check</a></li>
    </ul>
    """

def main():
    """Main entry point"""
    global exporter

    # Configuration from environment
    nginx_status_url = os.getenv('NGINX_STATUS_URL', 'http://nginx/nginx_status')
    nginx_json_url = os.getenv('NGINX_JSON_URL', 'http://nginx/status_json')
    scrape_interval = int(os.getenv('SCRAPE_INTERVAL', '15'))
    port = int(os.getenv('EXPORTER_PORT', '9113'))

    # Initialize exporter
    exporter = NginxPrometheusExporter(
        nginx_status_url=nginx_status_url,
        nginx_json_url=nginx_json_url,
        scrape_interval=scrape_interval
    )

    # Start Flask app
    logger.info(f"Starting NGINX Prometheus Exporter on port {port}")
    app.run(host='0.0.0.0', port=port, debug=False)

if __name__ == '__main__':
    main()