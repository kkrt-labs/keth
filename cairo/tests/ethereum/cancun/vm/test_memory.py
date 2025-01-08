from ethereum_types.bytes import Bytes
from ethereum_types.numeric import U256
from hypothesis import given
from hypothesis import strategies as st
from hypothesis.strategies import composite

from ethereum.cancun.vm.memory import buffer_read, memory_read_bytes, memory_write


@composite
def memory_write_strategy(draw):
    # NOTE: The testing strategy always assume that memory accesses are within bounds.
    # Because the memory is always extended to the proper size _before_ being accessed.
    memory_size = draw(st.integers(min_value=0, max_value=2**10))
    memory = draw(st.binary(min_size=memory_size, max_size=memory_size).map(bytearray))

    # Generate a start position in bounds with existing memory
    start_position = draw(st.integers(min_value=0, max_value=memory_size).map(U256))

    # Generate value with size that won't overflow memory
    max_value_size = memory_size - int(start_position)
    value = draw(st.binary(min_size=0, max_size=max_value_size))

    return memory, start_position, value


@composite
def memory_read_strategy(draw):
    memory_size = draw(st.integers(min_value=0, max_value=2**10))
    memory = draw(st.binary(min_size=memory_size, max_size=memory_size).map(bytearray))

    start_position = draw(st.integers(min_value=0, max_value=memory_size).map(U256))
    size = draw(
        st.integers(min_value=0, max_value=memory_size - int(start_position)).map(U256)
    )

    return memory, start_position, size


class TestMemory:
    @given(memory_write_strategy())
    def test_memory_write(self, cairo_run, params):
        memory, start_position, value = params
        cairo_memory = cairo_run("memory_write", memory, start_position, Bytes(value))
        memory_write(memory, start_position, Bytes(value))
        assert cairo_memory == memory

    @given(memory_read_strategy())
    def test_memory_read(self, cairo_run, params):
        memory, start_position, size = params
        (cairo_memory, cairo_value) = cairo_run(
            "memory_read_bytes", memory, start_position, size
        )
        python_value = memory_read_bytes(memory, start_position, size)
        assert cairo_memory == memory
        assert cairo_value == python_value

    @given(
        buffer=st.binary(min_size=0, max_size=2**10).map(Bytes),
        start_position=st.integers(min_value=0, max_value=2**128 - 1).map(U256),
        size=st.integers(min_value=0, max_value=2**10).map(U256),
    )
    def test_buffer_read(
        self, cairo_run, buffer: Bytes, start_position: U256, size: U256
    ):
        assert buffer_read(buffer, start_position, size) == cairo_run(
            "buffer_read", buffer, start_position, size
        )
