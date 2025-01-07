import pytest
from eth_utils import keccak
from ethereum_types.numeric import U256
from hypothesis import given
from hypothesis.strategies import binary

from src.utils.uint256 import int_to_uint256
from tests.utils.helpers import get_internal_storage_key

pytestmark = pytest.mark.python_vm


class TestAccount:
    class TestInit:
        @pytest.mark.parametrize(
            "address, code, nonce, balance",
            [(0, [], 0, 0), (2**160 - 1, [1, 2, 3], 1, 1)],
        )
        def test_should_return_account_with_default_dict_as_storage(
            self, cairo_run, address, code, nonce, balance
        ):
            code_hash_bytes = keccak(bytes(code))
            code_hash = int.from_bytes(code_hash_bytes, "big")
            cairo_run(
                "test__init__should_return_account_with_default_dict_as_storage",
                evm_address=address,
                code=code,
                nonce=nonce,
                balance_low=balance,
                code_hash=code_hash,
            )

    class TestCopy:
        @pytest.mark.parametrize(
            "address, code, nonce, balance",
            [(0, [], 0, 0), (2**160 - 1, [1, 2, 3], 1, 1)],
        )
        def test_should_return_new_account_with_same_attributes(
            self, cairo_run, address, code, nonce, balance
        ):
            code_hash_bytes = keccak(bytes(code))
            code_hash = int.from_bytes(code_hash_bytes, "big")
            cairo_run(
                "test__copy__should_return_new_account_with_same_attributes",
                evm_address=address,
                code=code,
                nonce=nonce,
                balance_low=balance,
                code_hash=code_hash,
            )

    class TestWriteStorage:
        @pytest.mark.parametrize("key, value", [(0, 0), (2**256 - 1, 2**256 - 1)])
        def test_should_store_value_at_key(self, cairo_run, key, value):
            cairo_run(
                "test__write_storage__should_store_value_at_key",
                key=int_to_uint256(key),
                value=int_to_uint256(value),
            )

    class TestComputeCodeHash:
        @given(bytecode=binary(min_size=0, max_size=400))
        def test_should_compute_code_hash(self, cairo_run, bytecode):
            output = cairo_run("test__compute_code_hash", code=bytecode)
            code_hash = int.from_bytes(keccak(bytecode), byteorder="big")
            assert output["low"] + 2**128 * output["high"] == code_hash

    class TestInternals:
        @given(key=...)
        def test_should_compute_storage_address(self, cairo_run, key: U256):
            assert get_internal_storage_key(key) == cairo_run(
                "test___storage_addr", key
            )
