import argparse
import json
import logging
from pathlib import Path

from cairo_addons.compiler import cairo_compile, implement_hints

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


def main():
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


def compile_keth():
    parser = argparse.ArgumentParser(description="Compile Cairo program")
    parser.add_argument(
        "--debug-info",
        action="store_true",
        default=False,
        help="Include debug information in the compiled program",
    )
    args = parser.parse_args()
    keth_main_path = Path("cairo/ethereum/cancun/main.cairo")
    proof_mode = True
    output_path = Path("build/main_compiled.json")
    logger.info(
        f"Compiling Keth with debug_info={args.debug_info} and proof_mode={proof_mode}"
    )
    program = cairo_compile(
        keth_main_path, debug_info=args.debug_info, proof_mode=proof_mode
    )
    with open(output_path, "w") as f:
        logger.info(f"Writing compiled program to {output_path}")
        json.dump(program.Schema().dump(program), f, indent=4, sort_keys=True)


if __name__ == "__main__":
    main()
