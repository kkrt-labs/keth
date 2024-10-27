from ethereum.cancun.blocks import Header
from ethereum.cancun.fork import (
    calculate_base_fee_per_gas,
    calculate_intrinsic_cost,
    check_gas_limit,
    validate_header,
)
from ethereum.cancun.transactions import AccessListTransaction
from ethereum.exceptions import InvalidBlock
from hypothesis import given

from tests.utils.errors import cairo_error
from tests.utils.models import BlockHeader, Transaction
from tests.utils.strategies import (
    access_list_transaction,
    block_header,
    uint64,
    uint128,
)


class TestFork:
    @given(uint128, uint128)
    def test_check_gas_limit(self, cairo_run, gas_limit, parent_gas_limit):
        error = check_gas_limit(gas_limit, parent_gas_limit)
        if not error:
            with cairo_error("InvalidBlock"):
                cairo_run(
                    "test_check_gas_limit",
                    gas_limit=gas_limit,
                    parent_gas_limit=parent_gas_limit,
                )
        else:
            cairo_run(
                "test_check_gas_limit",
                gas_limit=gas_limit,
                parent_gas_limit=parent_gas_limit,
            )

    @given(uint64, uint64, uint64, uint64)
    def test_calculate_base_fee_per_gas(
        self,
        cairo_run,
        block_gas_limit,
        parent_gas_limit,
        parent_gas_used,
        parent_base_fee_per_gas,
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
                "test_calculate_base_fee_per_gas",
                block_gas_limit=block_gas_limit,
                parent_gas_limit=parent_gas_limit,
                parent_gas_used=parent_gas_used,
                parent_base_fee_per_gas=parent_base_fee_per_gas,
            )
        else:
            with cairo_error("InvalidBlock"):
                cairo_run(
                    "test_calculate_base_fee_per_gas",
                    block_gas_limit=block_gas_limit,
                    parent_gas_limit=parent_gas_limit,
                    parent_gas_used=parent_gas_used,
                    parent_base_fee_per_gas=parent_base_fee_per_gas,
                )

    @given(header=block_header, parent_header=block_header)
    def test_validate_header(self, cairo_run, header, parent_header):
        error = None
        try:
            validate_header(Header(**header), Header(**parent_header))
        except InvalidBlock as e:
            error = e

        if error is not None:
            with cairo_error("InvalidBlock"):
                cairo_run(
                    "test_validate_header",
                    header=BlockHeader.model_validate(header),
                    parent_header=BlockHeader.model_validate(parent_header),
                )
        else:
            cairo_run(
                "test_validate_header",
                header=BlockHeader.model_validate(header),
                parent_header=BlockHeader.model_validate(parent_header),
            )

    @given(tx=access_list_transaction)
    def test_calculate_intrinsic_cost(self, cairo_run, tx):
        assert calculate_intrinsic_cost(AccessListTransaction(**tx)) == cairo_run(
            "test_calculate_intrinsic_cost", tx=Transaction.model_validate(tx)
        )
