import pytest
from ethereum_types.numeric import U256, Uint
from hypothesis import example, given
from hypothesis.strategies import integers

from ethereum.cancun.vm.gas import (
    calculate_gas_extend_memory,
    calculate_memory_gas_cost,
)
from tests.utils.strategies import uint128

pytestmark = pytest.mark.python_vm


class TestGas:
    class TestCost:
        @given(max_offset=integers(min_value=0, max_value=0xFFFFFF))
        def test_should_return_same_as_execution_specs(self, cairo_run, max_offset):
            output = cairo_run("test__memory_cost", words_len=(max_offset + 31) // 32)
            assert calculate_memory_gas_cost(Uint(max_offset)) == Uint(output)

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
            cost_before = calculate_memory_gas_cost(Uint(bytes_len))
            cost_after = calculate_memory_gas_cost(Uint(max_offset))
            diff = cost_after - cost_before
            assert diff == output

        @given(
            offset_1=...,
            size_1=...,
            offset_2=...,
            size_2=...,
            words_len=integers(
                min_value=0, max_value=0x3C0000
            ),  # upper bound reaching 30M gas limit on expansion
        )
        @example(
            offset_1=U256(2**200),
            size_1=U256(0),
            offset_2=U256(0),
            size_2=U256(1),
            words_len=1,
        )
        def test_should_return_max_expansion_cost(
            self,
            cairo_run,
            offset_1: U256,
            size_1: U256,
            offset_2: U256,
            size_2: U256,
            words_len: int,
        ):
            memory_cost_u32 = calculate_memory_gas_cost(Uint(2**32 - 1))
            output = cairo_run(
                "test__max_memory_expansion_cost",
                words_len=words_len,
                offset_1=offset_1,
                size_1=size_1,
                offset_2=offset_2,
                size_2=size_2,
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
                if (Uint(words_len * 32) + expansion.expand_by) >= Uint(2**32)
                else expansion.cost
            )
            assert output == expected_saturated

        @given(
            offset=...,
            size=...,
        )
        def test_memory_expansion_cost_saturated(
            self, cairo_run, offset: U256, size: U256
        ):
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
                total_expansion > U256(2**32)
                or total_expansion < offset
                or total_expansion < size
            ):
                cost = calculate_memory_gas_cost(Uint(2**32))
            else:
                cost = calculate_gas_extend_memory(b"", [(offset, size)]).cost

            assert cost == Uint(output)

    class TestMessageGas:
        @pytest.mark.parametrize(
            "gas_param, gas_left, expected",
            [
                (U256(0), 0, 0),
                (U256(10), 100, 10),
                (U256(100), 100, 99),
                (U256(100), 10, 10),
            ],
        )
        def test_should_return_message_base_gas(
            self, cairo_run, gas_param: U256, gas_left: int, expected
        ):
            output = cairo_run(
                "test__compute_message_call_gas",
                gas_param=gas_param,
                gas_left=gas_left,
            )
            assert output == expected
