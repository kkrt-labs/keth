import pytest
from eth_utils.address import to_checksum_address
from ethereum_types.numeric import U256
from hypothesis import example, given
from hypothesis.strategies import binary, integers
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from src.utils.uint256 import int_to_uint256
from tests.utils.strategies import Address


class TestMemoryOperations:
    class TestPc:
        @pytest.mark.parametrize("increment", list(range(1, 15)))
        def test_should_update_after_incrementing(self, cairo_run, increment):
            cairo_run(
                "test__exec_pc__should_return_evm_program_counter", increment=increment
            )

    class TestPop:
        def test_should_pop_an_item_from_execution_context(self, cairo_run):
            cairo_run("test__exec_pop_should_pop_an_item_from_execution_context")

    class TestMload:
        def test_should_load_a_value_from_memory(self, cairo_run):
            cairo_run("test__exec_mload_should_load_a_value_from_memory")

        def test_should_load_a_value_from_memory_with_memory_expansion(self, cairo_run):
            cairo_run(
                "test__exec_mload_should_load_a_value_from_memory_with_memory_expansion"
            )

        def test_should_load_a_value_from_memory_with_offset_larger_than_msize(
            self, cairo_run
        ):
            cairo_run(
                "test__exec_mload_should_load_a_value_from_memory_with_offset_larger_than_msize"
            )

    class TestMcopy:

        @given(
            memory_init_state=binary(min_size=1, max_size=100),
            size_mcopy=integers(min_value=1, max_value=100),
            src_offset_mcopy=integers(min_value=0, max_value=100),
            dst_offset_mcopy=integers(min_value=0, max_value=100),
        )
        def test_should_copy_a_value_from_memory(
            self,
            cairo_run,
            memory_init_state,
            size_mcopy,
            src_offset_mcopy,
            dst_offset_mcopy,
        ):
            (evm, memory) = cairo_run(
                "test__exec_mcopy",
                memory_init_state=memory_init_state,
                size_mcopy=int_to_uint256(size_mcopy),
                src_offset_mcopy=int_to_uint256(src_offset_mcopy),
                dst_offset_mcopy=int_to_uint256(dst_offset_mcopy),
            )
            expected_memory_state = list(memory_init_state) + [0] * (
                max(src_offset_mcopy, dst_offset_mcopy)
                + size_mcopy
                - len(memory_init_state)
            )
            expected_memory_state[dst_offset_mcopy : dst_offset_mcopy + size_mcopy] = (
                expected_memory_state[src_offset_mcopy : src_offset_mcopy + size_mcopy]
            )
            words_len = (len(expected_memory_state) + 31) // 32
            expected_memory_state = expected_memory_state + [0] * (
                words_len * 32 - len(expected_memory_state)
            )
            assert bytes.fromhex(memory) == bytes(expected_memory_state)

        @given(
            memory_init_state=binary(min_size=1, max_size=100),
            size_mcopy=integers(min_value=2**128, max_value=DEFAULT_PRIME - 1),
            src_offset_mcopy=integers(min_value=0, max_value=100),
            dst_offset_mcopy=integers(min_value=0, max_value=100),
        )
        @example(
            memory_init_state=b"a" * 100,
            size_mcopy=2**128 - 1,
            src_offset_mcopy=2**128 - 1,
            dst_offset_mcopy=0,
        )
        @example(
            memory_init_state=b"a" * 100,
            size_mcopy=2**128 - 1,
            src_offset_mcopy=0,
            dst_offset_mcopy=2**128 - 1,
        )
        def test_should_fail_if_memory_expansion_too_large(
            self,
            cairo_run,
            memory_init_state,
            size_mcopy,
            src_offset_mcopy,
            dst_offset_mcopy,
        ):
            (evm, memory) = cairo_run(
                "test__exec_mcopy",
                memory_init_state=memory_init_state,
                size_mcopy=int_to_uint256(size_mcopy),
                src_offset_mcopy=int_to_uint256(src_offset_mcopy),
                dst_offset_mcopy=int_to_uint256(dst_offset_mcopy),
            )
            assert evm["reverted"] == 2
            assert b"Kakarot: outOfGas left" in bytes(evm["return_data"])

    class TestMstore:

        @given(
            value=integers(min_value=0, max_value=2**256 - 1),
            offset=integers(min_value=0, max_value=0xFFFF),
        )
        def test_exec_mstore_should_store_a_value_in_memory(
            self, cairo_run, value, offset
        ):
            (evm, memory) = cairo_run(
                "test_exec_mstore",
                value=int_to_uint256(value),
                offset=int_to_uint256(offset),
            )

            expected_memory = (
                int.to_bytes(
                    value, length=(value.bit_length() + 7) // 8, byteorder="big"
                )
                if value > 0
                else b"\x00"
            )
            assert bytes.fromhex(memory)[offset : offset + 32] == bytes(
                [0] * (32 - len(expected_memory)) + list(expected_memory)
            )

        @given(
            value=integers(min_value=0, max_value=2**256 - 1),
            offset=integers(min_value=2**32, max_value=2**256 - 1),
        )
        def test_exec_mstore_should_fail_if_memory_expansion_too_large(
            self, cairo_run, value, offset
        ):
            (evm, _) = cairo_run(
                "test_exec_mstore",
                value=int_to_uint256(value),
                offset=int_to_uint256(offset),
            )
            assert evm["reverted"] == 2
            assert b"Kakarot: outOfGas left" in bytes(evm["return_data"])

    class TestSstore:
        def _verify_storage(self, state, address, expected_value):
            address_hex = to_checksum_address(f"0x{address:040x}")
            stored_value = list(state["accounts"][address_hex]["storage"].values())[0]
            low, high = stored_value.values()
            expected_low, expected_high = int_to_uint256(int(expected_value))
            assert low == expected_low
            assert high == expected_high

        @given(initial_value=..., key=..., address=...)
        def test_exec_sstore_should_store_same_value(
            self, cairo_run, initial_value: U256, key: U256, address: Address
        ):
            address = int.from_bytes(address, "big")
            state = cairo_run(
                "test_exec_sstore",
                initial_value=initial_value,
                new_value=initial_value,
                key=key,
                address=address,
            )
            self._verify_storage(state, address, initial_value)

        @given(initial_value=..., new_value=..., key=..., address=...)
        def test_exec_sstore_should_store_different_value(
            self,
            cairo_run,
            initial_value: U256,
            new_value: U256,
            key: U256,
            address: Address,
        ):
            address = int.from_bytes(address, "big")
            state = cairo_run(
                "test_exec_sstore",
                initial_value=initial_value,
                new_value=new_value,
                key=key,
                address=address,
            )
            self._verify_storage(state, address, new_value)
