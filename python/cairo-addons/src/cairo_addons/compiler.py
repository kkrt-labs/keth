import os
from pathlib import Path
from typing import Union

from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.cairo_compile import compile_cairo, get_module_reader
from starkware.cairo.lang.compiler.constants import LIBS_DIR_ENVVAR
from starkware.cairo.lang.compiler.preprocessor.default_pass_manager import (
    default_pass_manager,
)
from starkware.cairo.lang.compiler.program import CairoHint, Program

from cairo_addons.hints import implementations

TEST = "test"


def implement_hints(program: Program):
    return {
        k: [
            (
                CairoHint(
                    accessible_scopes=hint_.accessible_scopes,
                    flow_tracking_data=hint_.flow_tracking_data,
                    code=implementations.get(hint_.code, hint_.code),
                )
            )
            for hint_ in v
        ]
        for k, v in program.hints.items()
    }


def cairo_compile(
    path: Union[str, Path],
    debug_info: bool = False,
    proof_mode: bool = True,
    prime: int = DEFAULT_PRIME,
) -> Program:
    module_reader = get_module_reader(
        cairo_path=[
            str(Path(__file__).parents[4] / "cairo"),
            *os.getenv(LIBS_DIR_ENVVAR, "").split(":"),
        ]
    )

    pass_manager = default_pass_manager(prime=prime, read_module=module_reader.read)

    return compile_cairo(
        Path(path).read_text(),
        pass_manager=pass_manager,
        debug_info=debug_info,
        add_start=proof_mode,
    )
