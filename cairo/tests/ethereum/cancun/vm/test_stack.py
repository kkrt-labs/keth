from ethereum_types.numeric import U256

from ethereum.cancun.vm.stack import pop
from tests.utils.args_gen import Stack


class TestStack:
    def test_pop(self, cairo_run):
        initial_stack = Stack([U256(1)])
        assert pop(initial_stack.copy()) == cairo_run("pop", stack=initial_stack)
        # Todo: need to add a way for the runner to return as output variables the implicit arguments that are NOT builtins.
