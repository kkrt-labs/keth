import pytest
from ethereum.shanghai.vm.gas import (
    calculate_gas_extend_memory,
    calculate_memory_gas_cost,
    init_code_cost,
)
from hypothesis import given

from tests.utils.strategies import uint20, uint24, uint64, uint128, uint256


class TestGas:
    class TestCost:
        @given(max_offset=uint24)
        def test_memory_cost(self, cairo_run, max_offset):
            output = cairo_run("test__memory_cost", words_len=(max_offset + 31) // 32)
            assert calculate_memory_gas_cost(max_offset) == output

        @given(bytes_len=uint128, added_offset=uint128)
        def test_memory_expansion_cost(self, cairo_run, bytes_len, added_offset):
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

        @given(offset_1=uint20, size_1=uint20, offset_2=uint20, size_2=uint20)
        def test_max_memory_expansion_cost(
            self, cairo_run, offset_1, size_1, offset_2, size_2
        ):
            output = cairo_run(
                "test__max_memory_expansion_cost",
                words_len=0,
                offset_1=offset_1,
                size_1=size_1,
                offset_2=offset_2,
                size_2=size_2,
            )
            assert (
                output
                == calculate_gas_extend_memory(
                    b"",
                    [
                        (offset_1, size_1),
                        (offset_2, size_2),
                    ],
                ).cost
            )

        @given(offset=uint256, size=uint256)
        def test_memory_expansion_cost_saturated(self, cairo_run, offset, size):
            output = cairo_run(
                "test__memory_expansion_cost_saturated",
                words_len=0,
                offset=offset,
                size=size,
            )
            if size == 0:
                cost = 0
            elif offset + size > 2**32:
                cost = calculate_memory_gas_cost(2**32)
            else:
                cost = calculate_gas_extend_memory(b"", [(offset, size)]).cost

            assert cost == output

        @given(init_code_len=uint64)
        def test_init_code_cost(self, cairo_run, init_code_len):
            assert init_code_cost(init_code_len) == cairo_run(
                "test__init_code_cost", init_code_len=init_code_len
            )

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
                "test__compute_message_call_gas", gas_param=gas_param, gas_left=gas_left
            )
            assert output == expected
