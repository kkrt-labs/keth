from typing import Tuple

import pytest
from ethereum_types.bytes import Bytes20, Bytes32
from ethereum_types.numeric import U256
from hypothesis import given
from hypothesis import strategies as st
from hypothesis.strategies import composite

from ethereum.cancun.vm.instructions.storage import sload, tload
from tests.utils.args_gen import Evm
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import MAX_STORAGE_KEY_SET_SIZE

pytestmark = pytest.mark.python_vm


@composite
def evm_with_accessed_storage_keys(draw):
    accessed_storage_keys = draw(
        st.lists(
            st.from_type(Tuple[Bytes20, Bytes32]), max_size=MAX_STORAGE_KEY_SET_SIZE
        )
    )

    evm = draw(EvmBuilder().with_stack().with_env().with_gas_left().build())
    evm.accessed_storage_keys = set(accessed_storage_keys)
    use_random_key = draw(st.booleans())
    if not use_random_key and accessed_storage_keys:
        # Draw a key from the set and put it on top of the stack
        _, key = draw(st.sampled_from(accessed_storage_keys))
        evm.stack.insert(0, U256.from_be_bytes(key))

    return evm


class TestStorage:
    @given(evm=evm_with_accessed_storage_keys())
    def test_sload(self, cairo_run, evm: Evm):
        try:
            cairo_evm = cairo_run("sload", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                sload(evm)
            return

        sload(evm)
        assert evm == cairo_evm

    @given(evm=evm_with_accessed_storage_keys())
    def test_tload(self, cairo_run, evm: Evm):
        try:
            cairo_evm = cairo_run("tload", evm)
        except Exception as cairo_error:
            with pytest.raises(type(cairo_error)):
                tload(evm)
            return

        tload(evm)
        assert evm == cairo_evm
