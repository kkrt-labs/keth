from pathlib import Path

import click
from jinja2 import Environment, FileSystemLoader
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.identifier_definition import (
    FunctionDefinition,
    StructDefinition,
)

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


def format_return_value(i: int) -> str:
    """Format a return value for the template."""
    return f"cast(range_check96_ptr - {4 * (i + 1)}, UInt384*)"


def setup_jinja_env():
    """Set up the Jinja environment with the templates directory."""
    templates_dir = Path(__file__).parent / "templates"
    templates_dir.mkdir(parents=True, exist_ok=True)
    env = Environment(loader=FileSystemLoader(templates_dir))
    env.filters["format_return_value"] = format_return_value
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
def main(file_path: Path | None, prime: int):
    """Compile a Cairo file_path and extract its circuits."""
    if file_path is None:
        raise click.UsageError("File path is required (either as argument or with -f)")

    click.echo(f"Processing {file_path} with prime 0x{prime:x}")

    # Set up Jinja environment
    env = setup_jinja_env()
    header_template = env.get_template("header.cairo.j2")
    circuit_template = env.get_template("circuit.cairo.j2")

    # Compile the Cairo file
    program = cairo_compile(file_path, proof_mode=False, prime=prime)
    functions = [
        k.path[-1]
        for k, v in program.identifiers.as_dict().items()
        if isinstance(v, FunctionDefinition)
    ]
    if not functions:
        raise click.UsageError("No functions found in the file")

    # Generate output code
    output_parts = [header_template.render()]

    # Process each function
    for function in functions:
        circuit = circuit_compile(program, function)
        click.echo(f"Circuit {function}: {circuit}")

        # Render template with all necessary data
        circuit_code = circuit_template.render(
            name=function,
            args_struct=program.get_identifier(f"{function}.Args", StructDefinition),
            return_data_size=circuit["return_data_size"],
            circuit=circuit,
        )
        output_parts.append(circuit_code)

    # Write all circuits to output file
    output_path = file_path.parent / f"{file_path.stem}_compiled.cairo"
    output_path.write_text("\n\n".join(output_parts))
    click.echo(f"Generated circuit file: {output_path}")


if __name__ == "__main__":
    main()
