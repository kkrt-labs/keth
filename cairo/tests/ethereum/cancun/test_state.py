import pytest
from ethereum_types.bytes import Bytes32
from hypothesis import given

from ethereum.cancun.fork_types import Address
from ethereum.cancun.state import State, get_account, get_account_optional, get_storage
from tests.utils.strategies import address_strategy, key_strategy, state

pytestmark = pytest.mark.python_vm


class TestState:
    @given(state=state, address=address_strategy(state))
    def test_get_account(self, cairo_run, state: State, address: Address):
        [state_cairo, result_cairo] = cairo_run("get_account", state, address)
        result_py = get_account(state, address)
        assert result_cairo == result_py
        assert state_cairo == state

    @given(state=state, address=address_strategy(state))
    def test_get_account_optional(self, cairo_run, state: State, address: Address):
        [state_cairo, result_cairo] = cairo_run("get_account_optional", state, address)
        result_py = get_account_optional(state, address)
        assert result_cairo == result_py
        assert state_cairo == state

    @given(
        state=state,
        address=address_strategy(state),
        key=key_strategy(state, address_strategy(state)),
    )
    def test_get_storage(self, cairo_run, state: State, address: Address, key: Bytes32):
        [state_cairo, result_cairo] = cairo_run("get_storage", state, address, key)
        result_py = get_storage(state, address, key)
        assert result_cairo == result_py
        assert state_cairo == state
