import pytest

from ethereum.cancun.vm.gas import calculate_blob_gas_price
from tests.utils.data import block
from tests.utils.models import State

pytestmark = pytest.mark.python_vm


class TestBlockInformation:
    class TestBlobBaseFee:
        def test_should_push_blob_base_fee(self, cairo_run):
            block_ = block()
            [blob_base_fee] = cairo_run(
                "test__exec_blob_base_fee", block=block_, state=State.model_validate({})
            )

            expected = calculate_blob_gas_price(
                block_.block_header.excess_blob_gas_value
            )
            assert blob_base_fee == expected
