import pytest
from ethereum_types.numeric import Uint
from hypothesis import given

from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.stack import push_n
from tests.utils.args_gen import Evm
from tests.utils.strategies import evm_lite

pytestmark = pytest.mark.python_vm


def _test_push_n(cairo_run, evm: Evm, num_bytes: Uint):
    try:
        cairo_result = cairo_run("push_n", evm, num_bytes)
    except ExceptionalHalt as cairo_error:
        with pytest.raises(type(cairo_error)):
            push_n(evm, num_bytes)
        return

    push_n(evm, num_bytes)
    assert evm == cairo_result


class TestPushN:
    @given(evm=evm_lite)
    def test_push0(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(0))

    @given(evm=evm_lite)
    def test_push1(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(1))

    @given(evm=evm_lite)
    def test_push2(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(2))

    @given(evm=evm_lite)
    def test_push3(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(3))

    @given(evm=evm_lite)
    def test_push4(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(4))

    @given(evm=evm_lite)
    def test_push5(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(5))

    @given(evm=evm_lite)
    def test_push6(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(6))

    @given(evm=evm_lite)
    def test_push7(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(7))

    @given(evm=evm_lite)
    def test_push8(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(8))

    @given(evm=evm_lite)
    def test_push9(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(9))

    @given(evm=evm_lite)
    def test_push10(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(10))

    @given(evm=evm_lite)
    def test_push11(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(11))

    @given(evm=evm_lite)
    def test_push12(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(12))

    @given(evm=evm_lite)
    def test_push13(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(13))

    @given(evm=evm_lite)
    def test_push14(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(14))

    @given(evm=evm_lite)
    def test_push15(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(15))

    @given(evm=evm_lite)
    def test_push16(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(16))

    @given(evm=evm_lite)
    def test_push17(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(17))

    @given(evm=evm_lite)
    def test_push18(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(18))

    @given(evm=evm_lite)
    def test_push19(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(19))

    @given(evm=evm_lite)
    def test_push20(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(20))

    @given(evm=evm_lite)
    def test_push21(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(21))

    @given(evm=evm_lite)
    def test_push22(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(22))

    @given(evm=evm_lite)
    def test_push23(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(23))

    @given(evm=evm_lite)
    def test_push24(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(24))

    @given(evm=evm_lite)
    def test_push25(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(25))

    @given(evm=evm_lite)
    def test_push26(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(26))

    @given(evm=evm_lite)
    def test_push27(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(27))

    @given(evm=evm_lite)
    def test_push28(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(28))

    @given(evm=evm_lite)
    def test_push29(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(29))

    @given(evm=evm_lite)
    def test_push30(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(30))

    @given(evm=evm_lite)
    def test_push31(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(31))

    @given(evm=evm_lite)
    def test_push32(self, cairo_run, evm: Evm):
        _test_push_n(cairo_run, evm, Uint(32))
