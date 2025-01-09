import pytest
from hypothesis import given

from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.block import (
    block_hash,
    chain_id,
    coinbase,
    gas_limit,
    number,
    prev_randao,
    timestamp,
)
from tests.utils.args_gen import Evm
from tests.utils.strategies import evm_lite

pytestmark = pytest.mark.python_vm


class TestBlock:
    @given(evm=evm_lite)
    def test_block_hash(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("block_hash", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                block_hash(evm)
            return

        block_hash(evm)
        assert evm == cairo_result

    @given(evm=evm_lite)
    def test_coinbase(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("coinbase", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                coinbase(evm)
            return

        coinbase(evm)
        assert evm == cairo_result

    @given(evm=evm_lite)
    def test_timestamp(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("timestamp", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                timestamp(evm)
            return

        timestamp(evm)
        assert evm == cairo_result

    @given(evm=evm_lite)
    def test_number(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("number", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                number(evm)
            return

        number(evm)
        assert evm == cairo_result

    @given(evm=evm_lite)
    def test_prev_randao(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("prev_randao", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                prev_randao(evm)
            return

        prev_randao(evm)
        assert evm == cairo_result

    @given(evm=evm_lite)
    def test_gas_limit(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("gas_limit", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                gas_limit(evm)
            return

        gas_limit(evm)
        assert evm == cairo_result

    @given(evm=evm_lite)
    def test_chain_id(self, cairo_run, evm: Evm):
        try:
            cairo_result = cairo_run("chain_id", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                chain_id(evm)
            return

        chain_id(evm)
        assert evm == cairo_result
