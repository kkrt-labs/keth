import pytest
from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256
from hypothesis import given
from hypothesis import strategies as st
from hypothesis.strategies import composite

from ethereum.cancun.fork_types import Address
from ethereum.cancun.state import (
    get_account,
    get_account_optional,
    get_storage,
    get_transient_storage,
    set_storage,
)
from tests.utils.args_gen import TransientStorage
from tests.utils.strategies import address, bytes32, state, transient_storage_lite

pytestmark = pytest.mark.python_vm


@composite
def state_and_address_and_key(
    draw, state_strategy, address_strategy, key_strategy=None
):
    state = draw(state_strategy)

    # For address selection, use address_strategy if no keys in state
    address_options = (
        [st.sampled_from(list(state._main_trie._data.keys())), address_strategy]
        if state._main_trie._data != {}
        else [address_strategy]
    )
    address = draw(st.one_of(*address_options))

    # For key selection, use key_strategy if no storage keys for this address
    storage = state._storage_tries.get(address)
    if key_strategy is None:
        return state, address

    key_options = (
        [st.sampled_from(list(storage._data.keys())), key_strategy]
        if storage is not None and storage._data != {}
        else [key_strategy]
    )
    key = draw(st.one_of(*key_options))

    return state, address, key


class TestStateAccounts:
    @given(
        data=state_and_address_and_key(state_strategy=state, address_strategy=address),
    )
    def test_get_account(self, cairo_run, data):
        state, address = data
        [state_cairo, result_cairo] = cairo_run("get_account", state, address)
        result_py = get_account(state, address)
        assert result_cairo == result_py
        assert state_cairo == state

    @given(
        data=state_and_address_and_key(state_strategy=state, address_strategy=address)
    )
    def test_get_account_optional(self, cairo_run, data):
        state, address = data
        [state_cairo, result_cairo] = cairo_run("get_account_optional", state, address)
        result_py = get_account_optional(state, address)
        assert result_cairo == result_py
        assert state_cairo == state


class TestStateStorage:
    @given(
        data=state_and_address_and_key(
            state_strategy=state, address_strategy=address, key_strategy=bytes32
        )
    )
    def test_get_storage(
        self,
        cairo_run,
        data,
    ):
        state, address, key = data
        [state_cairo, result_cairo] = cairo_run("get_storage", state, address, key)
        result_py = get_storage(state, address, key)
        assert result_cairo == result_py
        assert state_cairo == state

    @given(
        data=state_and_address_and_key(
            state_strategy=state, address_strategy=address, key_strategy=bytes32
        ),
        value=...,
    )
    def test_set_storage(self, cairo_run, data, value: U256):
        state, address, key = data
        try:
            state_cairo = cairo_run("set_storage", state, address, key, value)
        except Exception as e:
            with pytest.raises(type(e)):
                set_storage(state, address, key, value)
            return

        set_storage(state, address, key, value)
        assert state_cairo == state


class TestTransientStorage:
    @given(
        transient_storage=transient_storage_lite,
        address=...,
        key=...,
    )
    def test_get_transient_storage(
        self,
        cairo_run,
        transient_storage: TransientStorage,
        address: Address,
        key: Bytes32,
    ):
        [transient_storage_cairo, result_cairo] = cairo_run(
            "get_transient_storage",
            transient_storage,
            address,
            key,
        )
        result_py = get_transient_storage(transient_storage, address, key)
        assert result_cairo == result_py
        assert transient_storage_cairo == transient_storage
