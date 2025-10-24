#!/usr/bin/env python3
"""
Simple test web application for pdeploy testing.
This is a basic Flask app that demonstrates deployment.
"""

from flask import Flask, jsonify
from datetime import datetime
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('TestWebApp')

app = Flask(__name__)


@app.route('/')
def index():
    """Home page."""
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Test Web App</title>
        <style>
            body {
                font-family: Arial, sans-serif;
                max-width: 800px;
                margin: 50px auto;
                padding: 20px;
                background-color: #f5f5f5;
            }
            .container {
                background-color: white;
                padding: 30px;
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            }
            h1 {
                color: #333;
            }
            .status {
                color: #28a745;
                font-weight: bold;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Test Web Application</h1>
            <p class="status">✓ Application is running successfully!</p>
            <p>This is a test web application deployed using pdeploy scripts.</p>
            <p><a href="/api/status">Check API Status</a></p>
            <p><a href="/api/health">Health Check</a></p>
        </div>
    </body>
    </html>
    """


@app.route('/api/status')
def status():
    """API status endpoint."""
    return jsonify({
        'status': 'running',
        'timestamp': datetime.now().isoformat(),
        'message': 'Test web app is running successfully'
    })


@app.route('/api/health')
def health():
    """Health check endpoint."""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat()
    })


if __name__ == '__main__':
    logger.info("Starting test web application...")
    app.run(host='0.0.0.0', port=8080, debug=False)
