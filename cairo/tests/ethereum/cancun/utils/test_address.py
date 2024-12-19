from typing import Union

from ethereum_types.bytes import Bytes32
from ethereum_types.numeric import U256, Uint
from hypothesis import given

from ethereum.cancun.fork_types import Address
from ethereum.cancun.utils.address import (
    compute_contract_address,
    compute_create2_contract_address,
    to_address,
)


class TestAddress:

    @given(data=...)
    def test_to_address(self, cairo_run, data: Union[Uint, U256]):
        assert to_address(data) == cairo_run("to_address", data)

    @given(address=..., nonce=...)
    def test_compute_contract_address(self, cairo_run, address: Address, nonce: Uint):
        assert compute_contract_address(address, nonce) == cairo_run(
            "compute_contract_address", address, nonce
        )

    @given(address=..., salt=..., call_data=...)
    def test_compute_create2_contract_address(
        self, cairo_run, address: Address, salt: Bytes32, call_data: bytearray
    ):
        assert compute_create2_contract_address(address, salt, call_data) == cairo_run(
            "compute_create2_contract_address", address, salt, call_data
        )
