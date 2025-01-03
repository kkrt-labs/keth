import json
from pathlib import Path

import pytest
from cairo_addons.vm import Program as RustProgram
from hypothesis import strategies as st
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


@pytest.fixture(scope="module")
def program_path():
    return Path(__file__).parent / "os.json"


@pytest.fixture(scope="module")
def sw_program(program_path):
    return SWProgram.load(data=json.loads(program_path.read_text()))


@pytest.fixture(scope="module")
def program_bytes(sw_program):
    return json.dumps(sw_program.Schema().dump(sw_program)).encode()


@pytest.fixture
def rust_program(program_bytes):
    return RustProgram.from_bytes(program_bytes)
