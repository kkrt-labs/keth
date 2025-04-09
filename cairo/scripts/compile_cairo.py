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


def compile_cairo(
    path,
    debug_info=False,
    proof_mode=True,
    should_implement_hints=True,
    output_path=None,
):
    logger.info(
        f"Compiling {path} with\n{debug_info=}\n{proof_mode=}\n{should_implement_hints=}\n{output_path=}"
    )
    input_path = Path(path)
    if output_path is None:
        output_path = input_path.with_suffix(".json")
    program = cairo_compile(
        path=input_path,
        debug_info=debug_info,
        proof_mode=proof_mode,
    )
    if should_implement_hints:
        program.hints = implement_hints(program)

    with open(output_path, "w") as f:
        json.dump(program.Schema().dump(program), f, indent=4, sort_keys=True)


parser = argparse.ArgumentParser(description="Compile Cairo program")
parser.add_argument(
    "--debug-info",
    action="store_true",
    default=False,
    help="Include debug information in the compiled program",
)

parser.add_argument(
    "--implement-hints",
    action="store_true",
    dest="implement_hints",
    default=True,
    help="Implement hints in the compiled program",
)


def main():
    parser.add_argument(
        "path",
        default="cairo/ethereum/cancun/main.cairo",
        help="The Cairo file to compile",
    )
    parser.add_argument(
        "--proof-mode",
        action="store_true",
        default=False,
        help="Compile in proof mode",
    )
    parser.add_argument(
        "--output-path",
        type=str,
        help="The path to save the compiled program",
        required=False,
    )
    args = parser.parse_args()
    compile_cairo(
        args.path,
        args.debug_info,
        args.proof_mode,
        args.implement_hints,
        args.output_path,
    )


def compile_keth():
    args = parser.parse_args()
    compile_cairo(
        Path("cairo/ethereum/cancun/main.cairo"),
        debug_info=args.debug_info,
        proof_mode=True,
        should_implement_hints=args.implement_hints,
        output_path=Path("build/main_compiled.json"),
    )


if __name__ == "__main__":
    main()
