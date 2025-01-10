import pytest
from hypothesis import given

from ethereum.cancun.fork_types import Address
from ethereum.cancun.state import State, get_account, get_account_optional

pytestmark = pytest.mark.python_vm


class TestState:
    @given(state=..., key=...)
    def test_get_account(self, cairo_run, state: State, key: Address):
        [state_cairo, result_cairo] = cairo_run("get_account", state, key)
        result_py = get_account(state, key)
        assert result_cairo == result_py
        assert state_cairo == state

    @given(state=..., key=...)
    def test_get_account_optional(self, cairo_run, state: State, key: Address):
        [state_cairo, result_cairo] = cairo_run("get_account_optional", state, key)
        result_py = get_account_optional(state, key)
        assert result_cairo == result_py
        assert state_cairo == state
