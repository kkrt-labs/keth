import json
import logging
import sys
from pathlib import Path

from tests.fixtures.compiler import cairo_compile
from tests.utils.hints import implement_hints

# Configure the logger
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def compile_cairo(file_name):
    input_path = Path(file_name)
    output_path = input_path.with_suffix(".json")
    program = cairo_compile(input_path, debug_info=False, proof_mode=True)
    program.hints = implement_hints(program)

    with open(output_path, "w") as f:
        json.dump(program.Schema().dump(program), f, indent=4, sort_keys=True)


def compile_os():
    compile_cairo(Path(__file__).parents[2] / "programs" / "os.cairo")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        logger.error("Usage: python compile_cairo.py <file_name>")
    else:
        compile_cairo(sys.argv[1])
