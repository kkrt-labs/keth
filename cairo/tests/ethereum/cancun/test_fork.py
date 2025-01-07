import pytest
from ethereum_types.numeric import Uint
from hypothesis import assume, given

from ethereum.cancun.blocks import Header
from ethereum.cancun.fork import (
    GAS_LIMIT_ADJUSTMENT_FACTOR,
    calculate_base_fee_per_gas,
    calculate_intrinsic_cost,
    check_gas_limit,
    validate_header,
)
from ethereum.cancun.transactions import Transaction
from ethereum.exceptions import InvalidBlock
from tests.utils.errors import cairo_error

pytestmark = pytest.mark.python_vm


class TestFork:
    @given(
        block_gas_limit=...,
        parent_gas_limit=...,
        parent_gas_used=...,
        parent_base_fee_per_gas=...,
    )
    def test_calculate_base_fee_per_gas(
        self,
        cairo_run,
        block_gas_limit: Uint,
        parent_gas_limit: Uint,
        parent_gas_used: Uint,
        parent_base_fee_per_gas: Uint,
    ):
        try:
            expected = calculate_base_fee_per_gas(
                block_gas_limit,
                parent_gas_limit,
                parent_gas_used,
                parent_base_fee_per_gas,
            )
        except InvalidBlock:
            expected = None

        if expected is not None:
            assert expected == cairo_run(
                "calculate_base_fee_per_gas",
                block_gas_limit,
                parent_gas_limit,
                parent_gas_used,
                parent_base_fee_per_gas,
            )
        else:
            with cairo_error("InvalidBlock"):
                cairo_run(
                    "calculate_base_fee_per_gas",
                    block_gas_limit,
                    parent_gas_limit,
                    parent_gas_used,
                    parent_base_fee_per_gas,
                )

    @given(header=..., parent_header=...)
    def test_validate_header(self, cairo_run, header: Header, parent_header: Header):
        error = None
        try:
            validate_header(header, parent_header)
        except InvalidBlock as e:
            error = e

        if error is not None:
            with cairo_error("InvalidBlock"):
                cairo_run("validate_header", header, parent_header)
        else:
            cairo_run("validate_header", header, parent_header)

    @given(tx=...)
    def test_calculate_intrinsic_cost(self, cairo_run, tx: Transaction):
        assert calculate_intrinsic_cost(tx) == cairo_run("calculate_intrinsic_cost", tx)

    @given(gas_limit=..., parent_gas_limit=...)
    def test_check_gas_limit(self, cairo_run, gas_limit: Uint, parent_gas_limit: Uint):
        assume(
            parent_gas_limit + parent_gas_limit // GAS_LIMIT_ADJUSTMENT_FACTOR
            < Uint(2**64)
        )
        assert check_gas_limit(gas_limit, parent_gas_limit) == cairo_run(
            "check_gas_limit", gas_limit, parent_gas_limit
        )
