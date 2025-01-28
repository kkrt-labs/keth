from hypothesis import given

from ethereum.cancun.transactions import (
    Transaction,
    calculate_intrinsic_cost,
    validate_transaction,
)
from tests.utils.errors import strict_raises


class TestTransactions:
    @given(tx=...)
    def test_calculate_intrinsic_cost(self, cairo_run, tx: Transaction):
        assert calculate_intrinsic_cost(tx) == cairo_run("calculate_intrinsic_cost", tx)

    @given(tx=...)
    def test_validate_transaction(self, cairo_run_py, tx: Transaction):
        """
        Test that transaction validation in Cairo matches Python implementation
        """
        try:
            result_cairo = cairo_run_py("validate_transaction", tx)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                validate_transaction(tx)
            return

        assert result_cairo == validate_transaction(tx)
