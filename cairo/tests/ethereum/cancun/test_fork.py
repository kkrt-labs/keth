from typing import Optional, Tuple

import pytest
from ethereum_types.bytes import Bytes
from ethereum_types.numeric import Uint
from hypothesis import assume, given
from hypothesis import strategies as st
from hypothesis.strategies import composite

from ethereum.cancun.blocks import Header, Log
from ethereum.cancun.fork import (
    GAS_LIMIT_ADJUSTMENT_FACTOR,
    calculate_base_fee_per_gas,
    check_gas_limit,
    make_receipt,
    process_transaction,
    validate_header,
)
from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
    Transaction,
)
from ethereum.cancun.vm import Environment
from ethereum.exceptions import EthereumException
from tests.utils.errors import strict_raises
from tests.utils.strategies import address, bytes32

pytestmark = pytest.mark.python_vm


@composite
def tx_without_code(draw):
    # Generate access list
    access_list_entries = draw(
        st.lists(st.tuples(address, st.lists(bytes32, max_size=2)), max_size=3)
    )
    access_list = tuple(
        (addr, tuple(storage_keys)) for addr, storage_keys in access_list_entries
    )

    # Define strategies for each transaction type
    legacy_tx = st.builds(LegacyTransaction, data=st.just(Bytes(bytes.fromhex("6060"))))

    access_list_tx = st.builds(
        AccessListTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        access_list=st.just(access_list),
    )

    fee_market_tx = st.builds(
        FeeMarketTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        access_list=st.just(access_list),
    )

    blob_tx = st.builds(
        BlobTransaction,
        data=st.just(Bytes(bytes.fromhex("6060"))),
        access_list=st.just(access_list),
    )

    # Choose one transaction type
    tx = draw(st.one_of(legacy_tx, access_list_tx, fee_market_tx, blob_tx))

    return tx


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
            cairo_result = cairo_run(
                "calculate_base_fee_per_gas",
                block_gas_limit,
                parent_gas_limit,
                parent_gas_used,
                parent_base_fee_per_gas,
            )
        except Exception as e:
            with strict_raises(type(e)):
                calculate_base_fee_per_gas(
                    block_gas_limit,
                    parent_gas_limit,
                    parent_gas_used,
                    parent_base_fee_per_gas,
                )
            return

        assert cairo_result == calculate_base_fee_per_gas(
            block_gas_limit,
            parent_gas_limit,
            parent_gas_used,
            parent_base_fee_per_gas,
        )

    @given(header=..., parent_header=...)
    def test_validate_header(self, cairo_run, header: Header, parent_header: Header):
        try:
            cairo_run("validate_header", header, parent_header)
        except Exception as e:
            with strict_raises(type(e)):
                validate_header(header, parent_header)
            return

        validate_header(header, parent_header)

    @given(gas_limit=..., parent_gas_limit=...)
    def test_check_gas_limit(self, cairo_run, gas_limit: Uint, parent_gas_limit: Uint):
        assume(
            parent_gas_limit + parent_gas_limit // GAS_LIMIT_ADJUSTMENT_FACTOR
            < Uint(2**64)
        )
        assert check_gas_limit(gas_limit, parent_gas_limit) == cairo_run(
            "check_gas_limit", gas_limit, parent_gas_limit
        )

    @given(tx=..., error=..., cumulative_gas_used=..., logs=...)
    def test_make_receipt(
        self,
        cairo_run,
        tx: Transaction,
        error: Optional[EthereumException],
        cumulative_gas_used: Uint,
        logs: Tuple[Log, ...],
    ):
        assert make_receipt(tx, error, cumulative_gas_used, logs) == cairo_run(
            "make_receipt", tx, error, cumulative_gas_used, logs
        )

    @given(env=..., tx=tx_without_code())
    def test_process_transaction(self, cairo_run, tx: Transaction, env: Environment):
        try:
            gas_used_cairo, logs_cairo, error_cairo = cairo_run(
                "process_transaction", env, tx
            )
        except Exception as e:
            with strict_raises(type(e)):
                process_transaction(env, tx)
            return

        gas_used, logs, error = process_transaction(env, tx)
        assert gas_used_cairo == gas_used
        assert logs_cairo == logs
        assert error_cairo == error
