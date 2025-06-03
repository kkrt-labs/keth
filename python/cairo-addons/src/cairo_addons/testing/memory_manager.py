"""
Memory Management for pytest-xdist Workers

This module provides utilities to monitor memory usage during test execution
and pause workers when memory is insufficient to prevent CI crashes.
"""

import logging
import os
import time

try:
    import psutil

    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False

logger = logging.getLogger(__name__)


def get_memory_info():
    """Get current memory usage information."""
    if not PSUTIL_AVAILABLE:
        return None

    memory = psutil.virtual_memory()
    return {
        "total": memory.total / (1024**3),  # GB
        "available": memory.available / (1024**3),  # GB
        "percent_used": memory.percent,
        "free": memory.free / (1024**3),  # GB
    }


def wait_for_memory(
    min_available_gb: float = 2.0,
    check_interval: float = 1.0,
    max_wait_time: float = 120.0,  # 2 minutes max wait
) -> bool:
    """
    Wait until sufficient memory is available.

    Args:
        min_available_gb: Minimum available memory in GB
        check_interval: How often to check memory (seconds)
        max_wait_time: Maximum time to wait (seconds)

    Returns:
        True if memory is available, False if timed out
    """
    if not PSUTIL_AVAILABLE:
        return True  # Can't check, assume it's fine

    start_time = time.time()
    first_check = True

    while time.time() - start_time < max_wait_time:
        memory_info = get_memory_info()
        if not memory_info:
            return True  # Can't check, assume it's fine

        # Check if memory conditions are met
        memory_ok = memory_info["available"] >= min_available_gb

        if memory_ok:
            if not first_check:
                logger.info(
                    f"Memory available again: {memory_info['available']:.1f}GB free, "
                    f"{memory_info['percent_used']:.1f}% used"
                )
            return True

        if first_check:
            logger.warning(
                f"Waiting for memory: need {min_available_gb}GB free "
                f"(have {memory_info['available']:.1f}GB), "
                f"(current {memory_info['percent_used']:.1f}%)"
            )
            first_check = False

        time.sleep(check_interval)

    # Timed out
    memory_info = get_memory_info()
    logger.error(
        f"Timed out waiting for memory after {max_wait_time}s. "
        f"Current: {memory_info['available']:.1f}GB free, "
        f"{memory_info['percent_used']:.1f}% used"
    )
    return False


def get_memory_requirements_for_ci():
    """
    Get memory requirements optimized for CI environment.

    Returns:
        Dict with memory thresholds for CI
    """
    # Check if we're in a CI environment
    is_ci = any(
        env in os.environ
        for env in ["CI", "GITHUB_ACTIONS", "GITLAB_CI", "JENKINS_URL"]
    )

    if is_ci:
        # More conservative settings for CI
        return {
            "min_available_gb": 2.0,  # Need at least 2GB free
            "check_interval": 1.0,  # Check Every Second
            "max_wait_time": 60.0,
        }
    else:
        # More relaxed settings for local development
        return {
            "min_available_gb": 1.0,  # Need at least 1GB free
            "check_interval": 1.0,  # Check every second
            "max_wait_time": 60.0,
        }
