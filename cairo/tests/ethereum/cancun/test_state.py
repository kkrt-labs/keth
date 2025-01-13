import pytest
from ethereum_types.bytes import Bytes32
from hypothesis import given
from hypothesis import strategies as st

from ethereum.cancun.fork_types import Address
from ethereum.cancun.state import State, get_account, get_account_optional, get_storage
from tests.utils.strategies import address, bytes32, state

pytestmark = pytest.mark.python_vm


class TestState:
    @given(state=state, address=address, draw_address_from_state=st.booleans())
    def test_get_account(
        self, cairo_run, state: State, address: Address, draw_address_from_state: bool
    ):
        if draw_address_from_state and state._main_trie._data.keys():
            # drawing the first address from the state's main trie maintains randomness
            # since state addresses are drawn randomly as part of `state` strategy
            address = next(iter(state._main_trie._data))
        [state_cairo, result_cairo] = cairo_run("get_account", state, address)
        result_py = get_account(state, address)
        assert result_cairo == result_py
        assert state_cairo == state

    @given(state=state, address=address, draw_address_from_state=st.booleans())
    def test_get_account_optional(
        self, cairo_run, state: State, address: Address, draw_address_from_state: bool
    ):
        if draw_address_from_state and state._main_trie._data.keys():
            address = next(iter(state._main_trie._data))
        [state_cairo, result_cairo] = cairo_run("get_account_optional", state, address)
        result_py = get_account_optional(state, address)
        assert result_cairo == result_py
        assert state_cairo == state

    @given(
        state=state,
        address=address,
        draw_address_from_state=st.booleans(),
        key=bytes32,
        draw_key_from_state=st.booleans(),
    )
    def test_get_storage(
        self,
        cairo_run,
        state: State,
        address: Address,
        draw_address_from_state: bool,
        draw_key_from_state: bool,
        key: Bytes32,
    ):
        # if `draw_address_from_state` is true and there is at least one address in the state
        # we overwrite the address strategy with the first address from the state
        if draw_address_from_state and state._main_trie._data.keys():
            address = next(iter(state._main_trie._data))
        # if `draw_key_from_state` is true and there is at least one value in the storage trie for `address`
        # we overwrite the key strategy with the first key from the storage trie
        if (
            draw_key_from_state
            and state._storage_tries.get(address) is not None
            and state._storage_tries.get(address)._data.keys()
        ):
            key = next(iter(state._storage_tries.get(address)._data))
        [state_cairo, result_cairo] = cairo_run("get_storage", state, address, key)
        result_py = get_storage(state, address, key)
        assert result_cairo == result_py
        assert state_cairo == state
