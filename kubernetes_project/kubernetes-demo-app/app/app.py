#!/usr/bin/env python3

from flask import Flask, jsonify, request, g
import time
import logging
import os
import psutil
import signal
import uuid
from datetime import datetime

# Configure logging level from environment
logging.basicConfig(
    level=getattr(logging, os.environ.get('LOG_LEVEL', 'INFO').upper()),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Global application state
app_ready = True
startup_time = time.time()

# Configuration from environment variables
MIN_UPTIME_SECONDS = int(os.environ.get('MIN_UPTIME_SECONDS', '5'))
APP_VERSION = os.environ.get('APP_VERSION', '1.0.0')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'development')


def signal_handler(sig, frame):
    """Handle graceful shutdown signals"""
    global app_ready
    app_ready = False
    logger.info("Received shutdown signal, marking as not ready", extra={
        'signal': sig,
        'graceful_shutdown': True
    })


# Register shutdown handlers
signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)


@app.before_request
def before_request():
    """Add request correlation ID and start timing"""
    g.request_id = str(uuid.uuid4())[:8]
    g.start_time = time.time()


@app.after_request
def after_request(response):
    """Log request completion with performance metrics"""
    if hasattr(g, 'start_time') and hasattr(g, 'request_id'):
        duration_ms = (time.time() - g.start_time) * 1000
        logger.info("Request completed", extra={
            'request_id': g.request_id,
            'method': request.method,
            'path': request.path,
            'status_code': response.status_code,
            'duration_ms': round(duration_ms, 2),
            'user_agent': request.headers.get('User-Agent', 'unknown')[:100]
        })
    return response


@app.route('/', methods=['GET'])
def root():
    """API information endpoint"""
    return jsonify({
        'name': 'Kubernetes Demo API',
        'version': APP_VERSION,
        'environment': ENVIRONMENT,
        'description': 'Simple Flask API demonstrating Kubernetes deployment patterns',
        'endpoints': {
            '/': 'API information',
            '/hello': 'Simple greeting endpoint',
            '/healthz': 'Liveness probe for Kubernetes',
            '/readiness': 'Readiness probe for Kubernetes',
            '/metrics': 'Prometheus metrics for monitoring'
        },
        'uptime_seconds': round(time.time() - startup_time, 2),
        'timestamp': datetime.utcnow().isoformat(),
        'request_id': getattr(g, 'request_id', 'unknown')
    }), 200


@app.route('/hello', methods=['GET'])
def hello():
    """Simple greeting with pod information"""
    return jsonify({
        'message': 'Hello from Kubernetes Demo API!',
        'timestamp': datetime.utcnow().isoformat(),
        'version': APP_VERSION,
        'environment': ENVIRONMENT,
        'pod_info': {  # Kubernetes pod metadata
            'name': os.environ.get('POD_NAME', 'unknown'),
            'namespace': os.environ.get('POD_NAMESPACE', 'unknown'),
            'node': os.environ.get('NODE_NAME', 'unknown')
        },
        'request_id': getattr(g, 'request_id', 'unknown')
    }), 200


@app.route('/healthz', methods=['GET'])
def health_check():
    """Kubernetes liveness probe - returns 200 if app is alive"""
    try:
        current_time = time.time()
        uptime_seconds = current_time - startup_time

        # Basic health validations
        if uptime_seconds < 0:
            raise Exception("Invalid uptime calculation")

        # Check if app received shutdown signal
        if not app_ready:
            raise Exception("Application shutting down")

        logger.debug("Health check passed", extra={
            'request_id': getattr(g, 'request_id', 'unknown'),
            'uptime_seconds': uptime_seconds
        })

        return jsonify({
            'status': 'healthy',
            'uptime_seconds': round(uptime_seconds, 2),
            'timestamp': datetime.utcnow().isoformat(),
            'version': APP_VERSION,
            'request_id': getattr(g, 'request_id', 'unknown')
        }), 200

    except Exception as e:
        logger.error("Health check failed", extra={
            'request_id': getattr(g, 'request_id', 'unknown'),
            'error': str(e)
        })
        return jsonify({
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat(),
            'request_id': getattr(g, 'request_id', 'unknown')
        }), 500


@app.route('/readiness', methods=['GET'])
def readiness_check():
    """Kubernetes readiness probe - returns 200 when ready for traffic"""
    try:
        # Check if app is marked as ready (graceful shutdown)
        if not app_ready:
            return jsonify({
                'status': 'not_ready',
                'reason': 'Application not ready to serve traffic',
                'timestamp': datetime.utcnow().isoformat(),
                'request_id': getattr(g, 'request_id', 'unknown')
            }), 503

        current_time = time.time()
        uptime_seconds = current_time - startup_time

        # Require minimum uptime to prevent startup race conditions
        if uptime_seconds < MIN_UPTIME_SECONDS:
            return jsonify({
                'status': 'not_ready',
                'reason': f'Minimum uptime not reached ({uptime_seconds:.1f}s < {MIN_UPTIME_SECONDS}s)',
                'timestamp': datetime.utcnow().isoformat(),
                'request_id': getattr(g, 'request_id', 'unknown')
            }), 503

        logger.debug("Readiness check passed", extra={
            'request_id': getattr(g, 'request_id', 'unknown'),
            'uptime_seconds': uptime_seconds
        })

        return jsonify({
            'status': 'ready',
            'uptime_seconds': round(uptime_seconds, 2),
            'timestamp': datetime.utcnow().isoformat(),
            'request_id': getattr(g, 'request_id', 'unknown')
        }), 200

    except Exception as e:
        logger.error("Readiness check failed", extra={
            'request_id': getattr(g, 'request_id', 'unknown'),
            'error': str(e)
        })
        return jsonify({
            'status': 'not_ready',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat(),
            'request_id': getattr(g, 'request_id', 'unknown')
        }), 503


@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint - exposes application and system metrics"""
    try:
        current_time = time.time()
        uptime_seconds = current_time - startup_time

        # Get host system metrics (non-blocking call)
        cpu_percent = psutil.cpu_percent(interval=None)
        memory = psutil.virtual_memory()
        memory_percent = memory.percent

        # Get container resource limits from Kubernetes environment
        cpu_limit_millicores = float(os.environ.get('CPU_LIMIT_MILLICORES', '200'))
        memory_limit_bytes = int(os.environ.get('MEMORY_LIMIT_BYTES', '134217728'))

        # Generate Prometheus format metrics
        metrics_output = f'''# HELP demo_app_info Application information
# TYPE demo_app_info gauge
demo_app_info{{version="{APP_VERSION}",environment="{ENVIRONMENT}",pod="{os.environ.get('POD_NAME', 'unknown')}",node="{os.environ.get('NODE_NAME', 'unknown')}"}} 1

# HELP demo_app_uptime_seconds Total uptime of the application
# TYPE demo_app_uptime_seconds counter
demo_app_uptime_seconds {uptime_seconds:.2f}

# HELP demo_app_ready Application readiness status (1=ready, 0=not ready)
# TYPE demo_app_ready gauge
demo_app_ready {1 if app_ready else 0}

# Host system metrics (note: these reflect the host, not container limits)
# HELP demo_app_host_cpu_percent Host CPU utilization percentage
# TYPE demo_app_host_cpu_percent gauge
demo_app_host_cpu_percent {cpu_percent:.2f}

# HELP demo_app_host_memory_percent Host memory utilization percentage
# TYPE demo_app_host_memory_percent gauge
demo_app_host_memory_percent {memory_percent:.2f}

# HELP demo_app_host_memory_bytes Host memory usage in bytes
# TYPE demo_app_host_memory_bytes gauge
demo_app_host_memory_bytes {memory.used}

# Container resource configuration (for reference)
# HELP demo_app_cpu_limit_millicores Configured CPU limit in millicores
# TYPE demo_app_cpu_limit_millicores gauge
demo_app_cpu_limit_millicores {cpu_limit_millicores}

# HELP demo_app_memory_limit_bytes Configured memory limit in bytes
# TYPE demo_app_memory_limit_bytes gauge
demo_app_memory_limit_bytes {memory_limit_bytes}

# HELP demo_app_min_uptime_seconds Configured minimum uptime for readiness
# TYPE demo_app_min_uptime_seconds gauge
demo_app_min_uptime_seconds {MIN_UPTIME_SECONDS}
'''

        logger.debug("Metrics generated", extra={
            'request_id': getattr(g, 'request_id', 'unknown'),
            'host_cpu_percent': cpu_percent,
            'host_memory_percent': memory_percent,
            'uptime_seconds': uptime_seconds
        })

        return metrics_output, 200, {'Content-Type': 'text/plain; charset=utf-8'}

    except Exception as e:
        logger.error("Metrics generation failed", extra={
            'request_id': getattr(g, 'request_id', 'unknown'),
            'error': str(e)
        })
        return jsonify({
            'error': 'Internal Server Error',
            'message': 'Metrics generation failed',
            'request_id': getattr(g, 'request_id', 'unknown')
        }), 500


# Error handlers for better observability
@app.errorhandler(404)
def not_found(error):
    """Handle 404 errors with helpful response"""
    logger.warning("404 error", extra={
        'request_id': getattr(g, 'request_id', 'unknown'),
        'path': request.path,
        'method': request.method
    })
    return jsonify({
        'error': 'Not Found',
        'message': 'The requested endpoint does not exist',
        'available_endpoints': ['/', '/hello', '/healthz', '/readiness', '/metrics'],
        'request_id': getattr(g, 'request_id', 'unknown')
    }), 404


@app.errorhandler(500)
def internal_error(error):
    """Handle 500 errors with correlation ID"""
    logger.error("500 error", extra={
        'request_id': getattr(g, 'request_id', 'unknown'),
        'error': str(error)
    })
    return jsonify({
        'error': 'Internal Server Error',
        'message': 'An unexpected error occurred',
        'request_id': getattr(g, 'request_id', 'unknown')
    }), 500


@app.errorhandler(Exception)
def handle_exception(e):
    """Catch-all exception handler"""
    logger.error("Unhandled exception", extra={
        'request_id': getattr(g, 'request_id', 'unknown'),
        'exception': str(e),
        'type': type(e).__name__
    })
    return jsonify({
        'error': 'Internal Server Error',
        'message': 'An unexpected error occurred',
        'request_id': getattr(g, 'request_id', 'unknown')
    }), 500


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    debug_mode = os.environ.get('DEBUG', 'false').lower() == 'true'

    # Log startup information
    logger.info("Starting Kubernetes Demo API", extra={
        'port': port,
        'environment': ENVIRONMENT,
        'version': APP_VERSION,
        'debug': debug_mode,
        'min_uptime_seconds': MIN_UPTIME_SECONDS,
        'log_level': os.environ.get('LOG_LEVEL', 'INFO')
    })

    # Run Flask application on all interfaces for container networking
    app.run(
        host='0.0.0.0',
        port=port,
        debug=debug_mode
    )