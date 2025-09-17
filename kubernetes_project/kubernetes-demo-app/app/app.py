#!/usr/bin/env python3
"""
Simple Flask API for Kubernetes Demo
===================================

Endpoints:
- GET /hello - Simple greeting endpoint
- GET /healthz - Health check for liveness probe
- GET /readiness - Readiness check for readiness probe  
- GET /metrics - Prometheus metrics for observability

SRE Best Practices:
- Separate health and readiness checks
- Metrics exposure for monitoring
- Structured logging
- Graceful error handling
"""

from flask import Flask, jsonify, request
import time
import logging
import os
import psutil
from datetime import datetime

# Configure structured logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Application state for readiness checks
app_ready = True
startup_time = time.time()

@app.route('/hello', methods=['GET'])
def hello():
    """
    Simple greeting endpoint to demonstrate basic functionality
    """
    logger.info("Hello endpoint accessed", extra={
        'endpoint': '/hello',
        'method': 'GET',
        'user_agent': request.headers.get('User-Agent', 'unknown')
    })
    
    return jsonify({
        'message': 'Hello from Kubernetes Demo API!',
        'timestamp': datetime.utcnow().isoformat(),
        'version': '1.0.0',
        'environment': os.environ.get('ENVIRONMENT', 'development')
    }), 200

@app.route('/healthz', methods=['GET'])
def health_check():
    """
    Liveness probe endpoint
    
    Returns 200 if application is alive and functioning
    Used by Kubernetes to restart unhealthy pods
    """
    try:
        # Basic health checks
        current_time = time.time()
        uptime_seconds = current_time - startup_time
        
        # Simple health validation
        if uptime_seconds < 0:
            raise Exception("Invalid uptime calculation")
            
        logger.debug("Health check passed", extra={
            'endpoint': '/healthz',
            'uptime_seconds': uptime_seconds
        })
        
        return jsonify({
            'status': 'healthy',
            'uptime_seconds': round(uptime_seconds, 2),
            'timestamp': datetime.utcnow().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        return jsonify({
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }), 500

@app.route('/readiness', methods=['GET'])
def readiness_check():
    """
    Readiness probe endpoint
    
    Returns 200 when application is ready to serve traffic
    Used by Kubernetes to control traffic routing
    """
    try:
        # Check if app is marked as ready
        if not app_ready:
            return jsonify({
                'status': 'not_ready',
                'reason': 'Application not ready to serve traffic',
                'timestamp': datetime.utcnow().isoformat()
            }), 503
        
        # Additional readiness checks could include:
        # - Database connectivity
        # - External service dependencies
        # - Cache warmup status
        # For this demo, we'll keep it simple
        
        current_time = time.time()
        uptime_seconds = current_time - startup_time
        
        # Require minimum uptime before ready (prevents startup race conditions)
        min_uptime = 5  # 5 seconds
        if uptime_seconds < min_uptime:
            return jsonify({
                'status': 'not_ready',
                'reason': f'Minimum uptime not reached ({uptime_seconds:.1f}s < {min_uptime}s)',
                'timestamp': datetime.utcnow().isoformat()
            }), 503
        
        logger.debug("Readiness check passed", extra={
            'endpoint': '/readiness',
            'uptime_seconds': uptime_seconds
        })
        
        return jsonify({
            'status': 'ready',
            'uptime_seconds': round(uptime_seconds, 2),
            'timestamp': datetime.utcnow().isoformat()
        }), 200
        
    except Exception as e:
        logger.error(f"Readiness check failed: {str(e)}")
        return jsonify({
            'status': 'not_ready',
            'error': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }), 503

@app.route('/metrics', methods=['GET'])
def metrics():
    """
    Prometheus metrics endpoint for observability
    
    Exposes metrics in Prometheus format for scraping
    Demonstrates monitoring best practices
    """
    try:
        current_time = time.time()
        uptime_seconds = current_time - startup_time
        
        # Get system metrics
        cpu_percent = psutil.cpu_percent(interval=0.1)
        memory = psutil.virtual_memory()
        memory_percent = memory.percent
        
        # Generate Prometheus format metrics
        metrics_output = f"""# HELP demo_app_uptime_seconds Total uptime of the application
# TYPE demo_app_uptime_seconds counter
demo_app_uptime_seconds {uptime_seconds:.2f}

# HELP demo_app_cpu_usage_percent Current CPU usage percentage
# TYPE demo_app_cpu_usage_percent gauge  
demo_app_cpu_usage_percent {cpu_percent:.2f}

# HELP demo_app_memory_usage_percent Current memory usage percentage
# TYPE demo_app_memory_usage_percent gauge
demo_app_memory_usage_percent {memory_percent:.2f}

# HELP demo_app_ready Application readiness status (1=ready, 0=not ready)
# TYPE demo_app_ready gauge
demo_app_ready {1 if app_ready else 0}

# HELP demo_app_info Application information
# TYPE demo_app_info gauge
demo_app_info{{version="1.0.0",environment="{os.environ.get('ENVIRONMENT', 'development')}"}} 1
"""

        logger.debug("Metrics endpoint accessed", extra={
            'endpoint': '/metrics',
            'cpu_percent': cpu_percent,
            'memory_percent': memory_percent,
            'uptime_seconds': uptime_seconds
        })
        
        return metrics_output, 200, {'Content-Type': 'text/plain; charset=utf-8'}
        
    except Exception as e:
        logger.error(f"Metrics generation failed: {str(e)}")
        return f"# Error generating metrics: {str(e)}\n", 500, {'Content-Type': 'text/plain; charset=utf-8'}

@app.route('/', methods=['GET'])
def root():
    """
    Root endpoint with API information
    """
    return jsonify({
        'name': 'Kubernetes Demo API',
        'version': '1.0.0',
        'description': 'Simple Flask API demonstrating Kubernetes deployment patterns',
        'endpoints': {
            '/hello': 'Simple greeting endpoint',
            '/healthz': 'Liveness probe for Kubernetes',
            '/readiness': 'Readiness probe for Kubernetes', 
            '/metrics': 'Prometheus metrics for monitoring'
        },
        'timestamp': datetime.utcnow().isoformat()
    }), 200

# Error handlers for better observability
@app.errorhandler(404)
def not_found(error):
    logger.warning(f"404 error: {request.url}")
    return jsonify({
        'error': 'Not Found',
        'message': 'The requested endpoint does not exist',
        'available_endpoints': ['/hello', '/healthz', '/readiness', '/metrics']
    }), 404

@app.errorhandler(500)
def internal_error(error):
    logger.error(f"500 error: {str(error)}")
    return jsonify({
        'error': 'Internal Server Error',
        'message': 'An unexpected error occurred'
    }), 500

if __name__ == '__main__':
    logger.info("Starting Kubernetes Demo API", extra={
        'port': int(os.environ.get('PORT', 5000)),
        'environment': os.environ.get('ENVIRONMENT', 'development')
    })
    
    # Run the Flask application
    app.run(
        host='0.0.0.0',  # Listen on all interfaces for container networking
        port=int(os.environ.get('PORT', 5000)),
        debug=os.environ.get('DEBUG', 'false').lower() == 'true'
    )