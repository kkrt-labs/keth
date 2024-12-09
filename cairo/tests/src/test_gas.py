import pytest
from hypothesis import given
from hypothesis.strategies import integers

from ethereum.cancun.vm.gas import (
    calculate_gas_extend_memory,
    calculate_memory_gas_cost,
)
from src.utils.uint256 import int_to_uint256
from tests.utils.strategies import felt, uint128, uint256


class TestGas:
    class TestCost:
        @given(max_offset=integers(min_value=0, max_value=0xFFFFFF))
        def test_should_return_same_as_execution_specs(self, cairo_run, max_offset):
            output = cairo_run("test__memory_cost", words_len=(max_offset + 31) // 32)
            assert calculate_memory_gas_cost(max_offset) == output

        @given(
            bytes_len=uint128,
            added_offset=uint128,
        )
        def test_should_return_correct_expansion_cost(
            self, cairo_run, bytes_len, added_offset
        ):
            max_offset = bytes_len + added_offset
            output = cairo_run(
                "test__memory_expansion_cost",
                words_len=(bytes_len + 31) // 32,
                max_offset=max_offset,
            )
            cost_before = calculate_memory_gas_cost(bytes_len)
            cost_after = calculate_memory_gas_cost(max_offset)
            diff = cost_after - cost_before
            assert diff == output

        @given(
            offset_1=felt,
            size_1=felt,
            offset_2=felt,
            size_2=felt,
            words_len=integers(
                min_value=0, max_value=0x3C0000
            ),  # upper bound reaching 30M gas limit on expansion
        )
        def test_should_return_max_expansion_cost(
            self, cairo_run, offset_1, size_1, offset_2, size_2, words_len
        ):
            memory_cost_u32 = calculate_memory_gas_cost(2**32 - 1)
            output = cairo_run(
                "test__max_memory_expansion_cost",
                words_len=words_len,
                offset_1=int_to_uint256(offset_1),
                size_1=int_to_uint256(size_1),
                offset_2=int_to_uint256(offset_2),
                size_2=int_to_uint256(size_2),
            )
            expansion = calculate_gas_extend_memory(
                b"\x00" * 32 * words_len,
                [
                    (offset_1, size_1),
                    (offset_2, size_2),
                ],
            )

            # If the memory expansion is greater than 2**27 words of 32 bytes
            # We saturate it to the hardcoded value corresponding the the gas cost of a 2**32 memory size
            expected_saturated = (
                memory_cost_u32
                if (words_len * 32 + expansion.expand_by) >= 2**32
                else expansion.cost
            )
            assert output == expected_saturated

        @given(
            offset=uint256,
            size=uint256,
        )
        def test_memory_expansion_cost_saturated(self, cairo_run, offset, size):
            output = cairo_run(
                "test__memory_expansion_cost_saturated",
                words_len=0,
                offset=offset,
                size=size,
            )

            total_expansion = offset.wrapping_add(size)

            if size == 0:
                cost = 0
            elif (
                total_expansion > 2**32
                or total_expansion < offset
                or total_expansion < size
            ):
                cost = calculate_memory_gas_cost(2**32)
            else:
                cost = calculate_gas_extend_memory(b"", [(offset, size)]).cost

            assert cost == output

    class TestMessageGas:
        @pytest.mark.parametrize(
            "gas_param, gas_left, expected",
            [
                (0, 0, 0),
                (10, 100, 10),
                (100, 100, 99),
                (100, 10, 10),
            ],
        )
        def test_should_return_message_base_gas(
            self, cairo_run, gas_param, gas_left, expected
        ):
            output = cairo_run(
                "test__compute_message_call_gas",
                gas_param=int_to_uint256(gas_param),
                gas_left=gas_left,
            )
            assert output == expected
