import argparse
import json
import logging
from pathlib import Path

from src.utils.compiler import cairo_compile, implement_hints

# Configure the logger
logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


def compile_cairo(file_name, should_implement_hints=True):
    input_path = Path(file_name)
    output_path = input_path.with_suffix(".json")
    program = cairo_compile(input_path)
    if should_implement_hints:
        program.hints = implement_hints(program)

    with open(output_path, "w") as f:
        json.dump(program.Schema().dump(program), f, indent=4, sort_keys=True)


def compile_os():
    compile_cairo(Path(__file__).parents[2] / "programs" / "os.cairo")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Compile Cairo program")
    parser.add_argument("file_name", help="The Cairo file to compile")
    parser.add_argument(
        "--no-implement-hints",
        action="store_false",
        dest="implement_hints",
        default=True,
        help="Do not implement hints in the compiled program",
    )

    args = parser.parse_args()
    compile_cairo(args.file_name, args.implement_hints)
