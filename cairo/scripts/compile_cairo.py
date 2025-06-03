import argparse
import json
import logging
from pathlib import Path

from starkware.cairo.bootloaders.hash_program import compute_program_hash_chain

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
        logger.info(f"Writing compiled program to {output_path}")
        json.dump(program.Schema().dump(program), f, indent=4, sort_keys=True)

    # Compute program hash
    program_hash = compute_program_hash_chain(program=program, use_poseidon=True)
    logger.info(f"Computed program hash for {output_path.name}: 0x{program_hash:x}")

    return output_path.name, program_hash


def save_program_hashes(program_hashes, output_dir):
    """Save program hashes to a JSON file in the output directory."""
    hashes_file = Path(output_dir) / "program_hashes.json"
    with open(hashes_file, "w") as f:
        json.dump(program_hashes, f, indent=4, sort_keys=True)
    logger.info(f"Saved program hashes to {hashes_file}")


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
        default="cairo/ethereum/prague/keth/main.cairo",
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
    program_name, program_hash = compile_cairo(
        args.path,
        args.debug_info,
        args.proof_mode,
        args.implement_hints,
        args.output_path,
    )
    logger.info(
        f"Compilation complete. Program: {program_name}, Hash: 0x{program_hash:x}"
    )


def compile_keth():
    args = parser.parse_args()
    from concurrent.futures import ThreadPoolExecutor

    programs = [
        (
            Path("cairo/ethereum/prague/keth/init_main.cairo"),
            Path("build/init_compiled.json"),
        ),
        (
            Path("cairo/ethereum/prague/keth/main.cairo"),
            Path("build/main_compiled.json"),
        ),
        (
            Path("cairo/ethereum/prague/keth/body_main.cairo"),
            Path("build/body_compiled.json"),
        ),
        (
            Path("cairo/ethereum/prague/keth/teardown_main.cairo"),
            Path("build/teardown_compiled.json"),
        ),
        (
            Path("cairo/ethereum/cancun/keth/aggregator_main.cairo"),
            Path("build/aggregator_compiled.json"),
        ),
    ]

    for _, output_path in programs:
        if not output_path.exists():
            output_path.parent.mkdir(parents=True, exist_ok=True)

    program_hashes = {}

    with ThreadPoolExecutor() as executor:
        futures = [
            executor.submit(
                compile_cairo,
                program_path,
                debug_info=args.debug_info,
                proof_mode=True,
                should_implement_hints=args.implement_hints,
                output_path=output_path,
            )
            for program_path, output_path in programs
        ]

        for future in futures:
            program_name, program_hash = future.result()
            program_hashes[program_name] = program_hash

    # Save program hashes to JSON file
    save_program_hashes(program_hashes, "build")


if __name__ == "__main__":
    main()
