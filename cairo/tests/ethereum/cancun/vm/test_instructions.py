from ethereum.cancun.vm import Evm
from ethereum.cancun.vm.exceptions import InvalidOpcode
from ethereum.cancun.vm.instructions import Ops, op_implementation
from ethereum_types.numeric import U256, Uint
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from tests.utils.args_gen import Stack
from tests.utils.evm_builder import EvmBuilder
from tests.utils.strategies import uint8


# Limit the fuzzing to the minimum necessary to ensure all opcodes are tested
@given(
    evm=EvmBuilder()
    .with_stack(
        st.lists(st.from_type(U256), min_size=0, max_size=10).map(
            lambda x: Stack[U256](x)
        )
    )
    .with_gas_left(st.just(Uint(1000000)))
    .build(),
    opcode=uint8,
)
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
