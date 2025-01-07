import pytest
from ethereum_types.numeric import U256
from hypothesis import given
from hypothesis import strategies as st

from ethereum.cancun.vm.exceptions import ExceptionalHalt
from ethereum.cancun.vm.instructions.log import log0, log1, log2, log3, log4
from ethereum.cancun.vm.stack import push
from tests.ethereum.cancun.vm.test_memory import MAX_MEMORY_SIZE
from tests.utils.args_gen import Evm
from tests.utils.strategies import evm_lite


class TestLog:
    @given(
        evm=evm_lite,
        # We limit the memory size to MEMORY_SIZE, thus we parameterize start_index and size
        # to ensure the memory size after expansion is within bounds.
        start_index=st.integers(min_value=0, max_value=MAX_MEMORY_SIZE // 2).map(U256),
        size=st.integers(min_value=0, max_value=MAX_MEMORY_SIZE // 2).map(U256),
    )
    def test_log0(self, cairo_run, evm: Evm, start_index: U256, size: U256):
        """Test the LOG0 instruction by comparing Cairo and Python implementations"""
        push(evm.stack, start_index)
        push(evm.stack, size)
        try:
            cairo_result = cairo_run("log0", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                log0(evm)
            return

        log0(evm)
        assert evm == cairo_result

    @given(
        evm=evm_lite,
        start_index=st.integers(min_value=0, max_value=MAX_MEMORY_SIZE // 2).map(U256),
        size=st.integers(min_value=0, max_value=MAX_MEMORY_SIZE // 2).map(U256),
        topic1=st.integers(min_value=0, max_value=2**256 - 1).map(U256),
    )
    def test_log1(
        self, cairo_run, evm: Evm, start_index: U256, size: U256, topic1: U256
    ):
        """Test the LOG1 instruction by comparing Cairo and Python implementations"""
        push(evm.stack, start_index)
        push(evm.stack, size)
        push(evm.stack, topic1)
        try:
            cairo_result = cairo_run("log1", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                log1(evm)
            return

        log1(evm)
        assert evm == cairo_result

    @given(
        evm=evm_lite,
        start_index=st.integers(min_value=0, max_value=MAX_MEMORY_SIZE // 2).map(U256),
        size=st.integers(min_value=0, max_value=MAX_MEMORY_SIZE // 2).map(U256),
        topic1=st.integers(min_value=0, max_value=2**256 - 1).map(U256),
        topic2=st.integers(min_value=0, max_value=2**256 - 1).map(U256),
    )
    def test_log2(
        self,
        cairo_run,
        evm: Evm,
        start_index: U256,
        size: U256,
        topic1: U256,
        topic2: U256,
    ):
        """Test the LOG2 instruction by comparing Cairo and Python implementations"""
        push(evm.stack, start_index)
        push(evm.stack, size)
        push(evm.stack, topic1)
        push(evm.stack, topic2)
        try:
            cairo_result = cairo_run("log2", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                log2(evm)
            return

        log2(evm)
        assert evm == cairo_result

    @given(
        evm=evm_lite,
        start_index=st.integers(min_value=0, max_value=MAX_MEMORY_SIZE // 2).map(U256),
        size=st.integers(min_value=0, max_value=MAX_MEMORY_SIZE // 2).map(U256),
        topic1=st.integers(min_value=0, max_value=2**256 - 1).map(U256),
        topic2=st.integers(min_value=0, max_value=2**256 - 1).map(U256),
        topic3=st.integers(min_value=0, max_value=2**256 - 1).map(U256),
    )
    def test_log3(
        self,
        cairo_run,
        evm: Evm,
        start_index: U256,
        size: U256,
        topic1: U256,
        topic2: U256,
        topic3: U256,
    ):
        """Test the LOG3 instruction by comparing Cairo and Python implementations"""
        push(evm.stack, start_index)
        push(evm.stack, size)
        push(evm.stack, topic1)
        push(evm.stack, topic2)
        push(evm.stack, topic3)
        try:
            cairo_result = cairo_run("log3", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                log3(evm)
            return

        log3(evm)
        assert evm == cairo_result

    @given(
        evm=evm_lite,
        start_index=st.integers(min_value=0, max_value=MAX_MEMORY_SIZE // 2).map(U256),
        size=st.integers(min_value=0, max_value=MAX_MEMORY_SIZE // 2).map(U256),
        topic1=st.integers(min_value=0, max_value=2**256 - 1).map(U256),
        topic2=st.integers(min_value=0, max_value=2**256 - 1).map(U256),
        topic3=st.integers(min_value=0, max_value=2**256 - 1).map(U256),
        topic4=st.integers(min_value=0, max_value=2**256 - 1).map(U256),
    )
    def test_log4(
        self,
        cairo_run,
        evm: Evm,
        start_index: U256,
        size: U256,
        topic1: U256,
        topic2: U256,
        topic3: U256,
        topic4: U256,
    ):
        """Test the LOG4 instruction by comparing Cairo and Python implementations"""
        push(evm.stack, start_index)
        push(evm.stack, size)
        push(evm.stack, topic1)
        push(evm.stack, topic2)
        push(evm.stack, topic3)
        push(evm.stack, topic4)
        try:
            cairo_result = cairo_run("log4", evm)
        except ExceptionalHalt as cairo_error:
            with pytest.raises(type(cairo_error)):
                log4(evm)
            return

        log4(evm)
        assert evm == cairo_result
