from typing import Optional, Set, Tuple, Union

from ethereum_types.bytes import Bytes, Bytes0, Bytes32
from ethereum_types.numeric import U256, Uint
from hypothesis import given
from hypothesis import strategies as st

from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.state import set_account
from ethereum.cancun.utils.message import prepare_message
from ethereum.cancun.vm import Environment


@st.composite
def caller_nonce_non_zero(draw):
    caller_address: Address = draw(st.from_type(Address))
    nonce = draw(st.integers(min_value=1, max_value=2**64 - 1).map(Uint))
    account = Account(
        nonce=nonce, balance=draw(st.from_type(U256)), code=draw(st.from_type(Bytes))
    )
    env: Environment = draw(st.from_type(Environment))
    set_account(env.state, caller_address, account)

    return caller_address, env


class TestMessage:
    @given(
        caller_and_env=caller_nonce_non_zero(),
        target=...,
        value=...,
        data=...,
        gas=...,
        code_address=...,
        should_transfer_value=...,
        is_static=...,
        preaccessed_addresses=...,
        preaccessed_storage_keys=...,
    )
    def test_prepare_message(
        self,
        cairo_run_py,
        caller_and_env: Tuple[Address, Environment],
        target: Union[Bytes0, Address],
        value: U256,
        data: Bytes,
        gas: Uint,
        code_address: Optional[Address],
        should_transfer_value: bool,
        is_static: bool,
        preaccessed_addresses: Set[Address],
        preaccessed_storage_keys: Set[Tuple[Address, Bytes32]],
    ):
        caller, env = caller_and_env
        cairo_message = cairo_run_py(
            "prepare_message",
            caller,
            target,
            value,
            data,
            gas,
            env,
            code_address,
            should_transfer_value,
            is_static,
            preaccessed_addresses,
            preaccessed_storage_keys,
        )
        evm_message = prepare_message(
            caller,
            target,
            value,
            data,
            gas,
            env,
            code_address,
            should_transfer_value,
            is_static,
            preaccessed_addresses,
            preaccessed_storage_keys,
        )
        assert cairo_message == evm_message
