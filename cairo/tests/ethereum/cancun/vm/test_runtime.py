import pytest
from ethereum.cancun.vm.runtime import get_valid_jump_destinations
from ethereum_types.bytes import Bytes
from ethereum_types.numeric import Uint
from hypothesis import example, given

from cairo_addons.testing.errors import cairo_error
from tests.utils.solidity import get_contract


class TestRuntime:
    @given(code=...)
    @example(code=get_contract("Counter", "Counter").bytecode_runtime)
    @example(code=get_contract("ERC20", "KethToken").bytecode_runtime)
    def test_get_valid_jump_destinations(self, cairo_run_py, code: Bytes):
        output_cairo = cairo_run_py(
            "test__get_valid_jump_destinations", bytecode=list(code)
        )

        output_cairo = [output_cairo] if isinstance(output_cairo, int) else output_cairo
        assert get_valid_jump_destinations(code) == set(map(Uint, output_cairo))


class TestFinalizeJumpdests:
    @given(bytecode=...)
    @example(bytecode=get_contract("Counter", "Counter").bytecode_runtime)
    def test_should_pass(self, cairo_run_py, bytecode: Bytes):
        cairo_run_py(
            "test__finalize_jumpdests",
            bytecode=list(bytecode),
            valid_jumpdests=get_valid_jump_destinations(bytecode),
        )


class TestAssertValidJumpdest:
    @pytest.mark.parametrize(
        "jumpdest",
        get_valid_jump_destinations(
            get_contract("Counter", "Counter").bytecode_runtime
        ),
    )
    def test_should_pass_on_valid_jumpdest(self, cairo_run_py, jumpdest):
        cairo_run_py(
            "test__assert_valid_jumpdest",
            bytecode=list(get_contract("Counter", "Counter").bytecode_runtime),
            valid_jumpdest=[int(jumpdest), 1, 1],
        )

    def test_should_raise_if_jumpdest_but_false(self, cairo_run_py):
        with cairo_error("assert_valid_jumpdest: invalid jumpdest"):
            cairo_run_py(
                "test__assert_valid_jumpdest", bytecode=[0x5B], valid_jumpdest=[0, 0, 0]
            )

    @pytest.mark.parametrize("push", list(range(0x60, 0x80)))
    def test_should_raise_if_jumpdest_is_push_arg(self, cairo_run_py, push):
        with cairo_error("assert_valid_jumpdest: invalid jumpdest"):
            cairo_run_py(
                "test__assert_valid_jumpdest",
                bytecode=[push] + (push - 0x5F) * [0x5B],
                valid_jumpdest=[push - 0x5F, 1, 1],
            )
