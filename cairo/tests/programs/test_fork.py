from ethereum.cancun.blocks import Header
from ethereum.cancun.fork import (
    calculate_base_fee_per_gas,
    check_gas_limit,
    validate_header,
)
from ethereum.exceptions import InvalidBlock
from hypothesis import given
from hypothesis.strategies import integers

from tests.fixtures.data import block_header_strategy
from tests.utils.errors import cairo_error
from tests.utils.models import BlockHeader


class TestFork:
    @given(
        integers(min_value=0, max_value=2**128 - 1),
        integers(min_value=0, max_value=2**128 - 1),
    )
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

    @given(
        integers(min_value=0, max_value=2**128 - 1),
        integers(min_value=0, max_value=2**128 - 1),
        integers(min_value=0, max_value=2**128 - 1),
        integers(min_value=0, max_value=2**128 - 1),
    )
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

    @given(header=block_header_strategy, parent_header=block_header_strategy)
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
