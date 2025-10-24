#!/usr/bin/env python3
"""
Simple test bot application for pdeploy testing.
This bot logs messages every 10 seconds to demonstrate it's running.
"""

import time
import logging
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger('TestBot')


def main():
    """Main bot loop."""
    logger.info("Test bot started successfully!")
    logger.info("Bot is running and will log a message every 10 seconds...")

    counter = 0

    try:
        while True:
            counter += 1
            logger.info(f"Bot is alive! Counter: {counter}, Time: {datetime.now()}")
            time.sleep(10)
    except KeyboardInterrupt:
        logger.info("Bot stopped by user")
    except Exception as e:
        logger.error(f"Bot encountered an error: {e}")
        raise


if __name__ == "__main__":
    main()
