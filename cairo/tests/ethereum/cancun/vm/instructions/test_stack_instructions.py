import pytest
from hypothesis import given

import ethereum.cancun.vm.instructions.stack as stack
from ethereum.cancun.vm.exceptions import ExceptionalHalt
from tests.utils.args_gen import Evm
from tests.utils.strategies import evm_lite

pytestmark = pytest.mark.python_vm

PUSH_I = {
    0: stack.push0,
    1: stack.push1,
    2: stack.push2,
    3: stack.push3,
    4: stack.push4,
    5: stack.push5,
    6: stack.push6,
    7: stack.push7,
    8: stack.push8,
    9: stack.push9,
    10: stack.push10,
    11: stack.push11,
    12: stack.push12,
    13: stack.push13,
    14: stack.push14,
    15: stack.push15,
    16: stack.push16,
    17: stack.push17,
    18: stack.push18,
    19: stack.push19,
    20: stack.push20,
    21: stack.push21,
    22: stack.push22,
    23: stack.push23,
    24: stack.push24,
    25: stack.push25,
    26: stack.push26,
    27: stack.push27,
    28: stack.push28,
    29: stack.push29,
    30: stack.push30,
    31: stack.push31,
    32: stack.push32,
}

SWAP_I = {
    1: stack.swap1,
    2: stack.swap2,
    3: stack.swap3,
    4: stack.swap4,
    5: stack.swap5,
    6: stack.swap6,
    7: stack.swap7,
    8: stack.swap8,
    9: stack.swap9,
    10: stack.swap10,
    11: stack.swap11,
    12: stack.swap12,
    13: stack.swap13,
    14: stack.swap14,
    15: stack.swap15,
    16: stack.swap16,
}

DUP_I = {
    1: stack.dup1,
    2: stack.dup2,
    3: stack.dup3,
    4: stack.dup4,
    5: stack.dup5,
    6: stack.dup6,
    7: stack.dup7,
    8: stack.dup8,
    9: stack.dup9,
    10: stack.dup10,
    11: stack.dup11,
    12: stack.dup12,
    13: stack.dup13,
    14: stack.dup14,
    15: stack.dup15,
    16: stack.dup16,
}


class TestPushN:
    @pytest.mark.parametrize("num_bytes", range(33))
    @given(evm=evm_lite)
    def test_push_n(self, cairo_run, evm: Evm, num_bytes: int):
        try:
            func_name = f"push{num_bytes}"
            cairo_result = cairo_run(func_name, evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                PUSH_I[num_bytes](evm)
            return

        PUSH_I[num_bytes](evm)
        assert evm == cairo_result


class TestSwapN:
    @pytest.mark.parametrize("item_number", range(1, 17))
    @given(evm=evm_lite)
    def test_swap_n(self, cairo_run, evm: Evm, item_number: int):
        try:
            func_name = f"swap{item_number}"
            cairo_result = cairo_run(func_name, evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                SWAP_I[item_number](evm)
            return

        SWAP_I[item_number](evm)
        assert evm == cairo_result


class TestDupN:
    @pytest.mark.parametrize("item_number", range(1, 17))
    @given(evm=evm_lite)
    def test_dup_n(self, cairo_run, evm: Evm, item_number: int):
        try:
            func_name = f"dup{item_number}"
            cairo_result = cairo_run(func_name, evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                DUP_I[item_number](evm)
            return

        DUP_I[item_number](evm)
        assert evm == cairo_result
