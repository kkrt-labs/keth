import logging
from pathlib import Path

from dotenv import load_dotenv

logging.basicConfig()
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)
load_dotenv()

CAIRO_DIR = Path("src")
TESTS_DIR = Path("tests")
BUILD_DIR = Path("build")
BUILD_DIR.mkdir(exist_ok=True, parents=True)

CHAIN_ID = 1
