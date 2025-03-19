"""Circuit Compiler for Cairo Arithmetic Operations.

This script compiles Cairo functions into arithmetic circuits that can be
efficiently executed using the ModBuiltin operations. It is particularly useful for
cryptographic operations that involve heavy modular arithmetic.

The compilation process:
1. Takes a Cairo source file containing functions with UInt384 operations
2. Extracts the arithmetic operations (see compiler.py)
3. Outputs the compiled circuits in a new Cairo file

Key features:
- Supports selective compilation of specific functions
- Handles both addition and multiplication modulo operations
- Preserves function signatures and argument types

Usage:
    # Compile all functions in a file
    python compile_circuit.py input.cairo

    # Compile specific functions
    python compile_circuit.py input.cairo -fn func1 -fn func2

    # Print output to terminal instead of file
    python compile_circuit.py input.cairo -fn func1 -e

    # Use custom prime field
    python compile_circuit.py input.cairo -p 0x7b

Requirements:
    - Cairo source file with felt arithmetic operations
    - Functions must use standard argument and return type patterns
"""

import subprocess
from pathlib import Path

import click
from jinja2 import Environment, FileSystemLoader
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.identifier_definition import FunctionDefinition

from cairo_addons.compiler import cairo_compile
from cairo_ec.compiler import circuit_compile


class IntParamType(click.ParamType):
    name = "integer"

    def convert(self, value, param, ctx):
        try:
            if isinstance(value, int):
                return value
            if value.startswith("0x"):
                return int(value, 16)
            return int(value, 10)
        except ValueError:
            self.fail(f"{value!r} is not a valid integer", param, ctx)


INT = IntParamType()


def setup_jinja_env():
    """Set up the Jinja environment with the templates directory."""
    templates_dir = Path(__file__).parent / "templates"
    templates_dir.mkdir(parents=True, exist_ok=True)
    env = Environment(loader=FileSystemLoader(templates_dir))
    return env


@click.command()
@click.argument(
    "file_path",
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    required=False,
)
@click.option(
    "--file_path",
    "-f",
    type=click.Path(exists=True, dir_okay=False, path_type=Path),
    help="Path to the Cairo source file_path",
)
@click.option(
    "--prime",
    "-p",
    type=INT,
    default=DEFAULT_PRIME,
    help="Prime number to use (can be decimal like 123 or hex like 0x7b)",
)
@click.option(
    "--function",
    "-fn",
    multiple=True,
    help="Name of the function to compile. Can be specified multiple times. If not specified, all functions will be compiled.",
)
@click.option(
    "--echo",
    "-e",
    is_flag=True,
    help="echo the output to terminal instead of writing to a file",
)
def main(file_path: Path | None, prime: int, function: list[str], echo: bool):
    """Compile a Cairo file_path and extract its circuits."""
    if file_path is None:
        raise click.UsageError("File path is required (either as argument or with -f)")

    click.echo(f"Processing {file_path} with prime 0x{prime:x}")

    # Set up Jinja environment
    env = setup_jinja_env()
    header_template = env.get_template("header.cairo.j2")
    _struct_template = env.get_template("struct.cairo.j2")
    circuit_template = env.get_template("circuit.cairo.j2")

    # Compile the Cairo file
    program = cairo_compile(file_path, proof_mode=False, prime=prime)

    # Get all functions or filter by provided names
    available_functions = {
        k.path[-1]: k.path[-1]
        for k, v in program.identifiers.as_dict().items()
        if isinstance(v, FunctionDefinition)
    }

    if not available_functions:
        raise click.UsageError("No functions found in the file")

    # If no functions specified, use all available ones
    functions_to_compile = function or available_functions.keys()

    # Validate requested functions exist
    unknown_functions = set(functions_to_compile) - set(available_functions)
    if unknown_functions:
        raise click.UsageError(
            f"Unknown functions: {', '.join(unknown_functions)}. "
            f"Available functions are: {', '.join(available_functions)}"
        )

    # Generate output code
    output_parts = [header_template.render()]
    circuit_parts = []

    struct_names = set()
    structs_to_render = []

    # Process each function
    for function_name in functions_to_compile:
        circuit = circuit_compile(program, function_name)
        click.echo(f"Circuit {function_name}: {circuit}")

        # Extract only new structs that are not used in previously compiled functions
        # and not part of the imports
        for struct in circuit["structs"]:
            struct_name = struct["name"]
            # Check if struct is not already processed and not in imports
            if struct_name not in struct_names:
                struct_names.add(struct_name)
                structs_to_render.append(struct)

        # Render template with all necessary data
        circuit_code = circuit_template.render(name=function_name, circuit=circuit)
        circuit_parts.append(circuit_code)

    # Render the structs
    struct_code = _struct_template.render(structs=structs_to_render)
    output_parts.append(struct_code)

    # Properly order the compiled function
    # Imports, Structs, Functions
    output_parts = output_parts + circuit_parts

    # Join all parts with double newlines
    output = "\n\n".join(output_parts)

    if echo:
        # echo to terminal
        click.echo(output)
    else:
        # Write to file and format
        output_path = file_path.parent / f"{file_path.stem}_compiled.cairo"
        output_path.write_text(output)
        subprocess.run(
            ["trunk", "fmt", str(output_path)],
            check=False,
            capture_output=True,
            text=True,
        )
        click.echo(f"Generated circuit file: {output_path}")


if __name__ == "__main__":
    main()
