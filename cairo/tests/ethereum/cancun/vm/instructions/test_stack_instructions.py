import pytest
from hypothesis import given

from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.stack import (
    push0,
    push1,
    push2,
    push3,
    push4,
    push5,
    push6,
    push7,
    push8,
    push9,
    push10,
    push11,
    push12,
    push13,
    push14,
    push15,
    push16,
    push17,
    push18,
    push19,
    push20,
    push21,
    push22,
    push23,
    push24,
    push25,
    push26,
    push27,
    push28,
    push29,
    push30,
    push31,
    push32,
)
from tests.utils.args_gen import Evm
from tests.utils.strategies import evm_lite

pytestmark = pytest.mark.python_vm

PUSH_I = {
    0: push0,
    1: push1,
    2: push2,
    3: push3,
    4: push4,
    5: push5,
    6: push6,
    7: push7,
    8: push8,
    9: push9,
    10: push10,
    11: push11,
    12: push12,
    13: push13,
    14: push14,
    15: push15,
    16: push16,
    17: push17,
    18: push18,
    19: push19,
    20: push20,
    21: push21,
    22: push22,
    23: push23,
    24: push24,
    25: push25,
    26: push26,
    27: push27,
    28: push28,
    29: push29,
    30: push30,
    31: push31,
    32: push32,
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
