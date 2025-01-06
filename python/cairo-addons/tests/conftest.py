import json
from pathlib import Path

import pytest
from cairo_addons.vm import Program as RustProgram
from hypothesis import strategies as st
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.cairo_compile import compile_cairo, get_module_reader
from starkware.cairo.lang.compiler.preprocessor.default_pass_manager import (
    default_pass_manager,
)
from starkware.cairo.lang.compiler.program import Program as SWProgram
from starkware.cairo.lang.vm.relocatable import RelocatableValue

st.register_type_strategy(
    RelocatableValue,
    st.fixed_dictionaries(
        {
            "segment_index": st.integers(
                min_value=0, max_value=2**RelocatableValue.SEGMENT_BITS - 1
            ),
            "offset": st.integers(
                min_value=0, max_value=2**RelocatableValue.OFFSET_BITS - 1
            ),
        }
    ).map(lambda x: RelocatableValue(**x)),
)


@pytest.fixture(scope="session")
def sw_program():
    module_reader = get_module_reader(cairo_path=[str(Path(__file__).parents[2])])

    pass_manager = default_pass_manager(
        prime=DEFAULT_PRIME, read_module=module_reader.read
    )

    return compile_cairo(
        (Path(__file__).parent / "os.cairo").read_text(),
        pass_manager=pass_manager,
        debug_info=False,
        add_start=False,
    )


@pytest.fixture(scope="module")
def program_bytes(sw_program: SWProgram):
    return json.dumps(sw_program.Schema().dump(sw_program)).encode()


@pytest.fixture
def rust_program(program_bytes):
    return RustProgram.from_bytes(program_bytes)
