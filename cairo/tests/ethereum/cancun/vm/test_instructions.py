from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.exceptions import InvalidOpcode
from ethereum.cancun.vm.instructions import Ops, op_implementation
from hypothesis import given

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import uint8


@given(evm=EvmBuilder().with_stack().with_gas_left().build(), opcode=uint8)
def test_op_implementation(cairo_run, evm: Evm, opcode):
    try:
        cairo_evm = cairo_run("test_op_implementation", evm, opcode)
    except Exception as e:
        with strict_raises(type(e)):
            try:
                op = Ops(opcode)
            except ValueError as e:
                raise InvalidOpcode(opcode)
            op_implementation[op](evm)
        return

    op = Ops(opcode)
    op_implementation[op](evm)
    assert evm == cairo_evm
