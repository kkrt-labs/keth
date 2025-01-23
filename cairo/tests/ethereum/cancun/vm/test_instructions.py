from hypothesis import given

from ethereum.cancun.vm.exceptions import InvalidOpcode
from ethereum.cancun.vm.instructions import Ops, op_implementation
from tests.utils.args_gen import Evm
from tests.utils.errors import strict_raises
from tests.utils.strategies import uint8

# TODO: remove when implemented
unimplemented_opcodes = [0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xFA, 0xFF]


@given(evm=..., opcode=uint8.filter(lambda x: x not in unimplemented_opcodes))
def test_op_implementation(cairo_run, evm: Evm, opcode):
    try:
        cairo_evm = cairo_run("op_implementation", evm, opcode)
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
