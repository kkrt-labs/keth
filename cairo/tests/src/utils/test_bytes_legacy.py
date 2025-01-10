import pytest
from hypothesis import given
from hypothesis.strategies import binary, integers
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

from src.utils.uint256 import int_to_uint256
from tests.utils.errors import cairo_error
from tests.utils.hints import patch_hint

pytestmark = pytest.mark.python_vm


class TestBytes:
    class TestFeltToAscii:
        @pytest.mark.parametrize("n", [0, 10, 1234, 0xFFFFFF])
        def test_should_return_ascii(self, cairo_run, n):
            output = cairo_run("test__felt_to_ascii", n=n)
            assert (
                str(n)
                == bytes(output if isinstance(output, list) else [output]).decode()
            )

    class TestFeltToBytesLittle:
        @given(n=integers(min_value=0, max_value=2**248 - 1))
        def test_should_return_bytes(self, cairo_run, n):
            output = cairo_run("test__felt_to_bytes_little", n=n)
            expected = (
                int.to_bytes(n, length=(n.bit_length() + 7) // 8, byteorder="little")
                if n > 0
                else b"\x00"
            )
            assert expected == bytes(output)

        @given(n=integers(min_value=2**248, max_value=DEFAULT_PRIME - 1))
        def test_should_raise_when_value_sup_31_bytes(self, cairo_run, n):
            with cairo_error(message="felt_to_bytes_little: value >= 2**248"):
                cairo_run("test__felt_to_bytes_little", n=n)

        # This test checks the function fails if the % base is removed from the hint
        # All values up to 256 will have the same decomposition if the it is removed
        @given(n=integers(min_value=256, max_value=2**248 - 1))
        def test_should_raise_when_byte_value_not_modulo_base(
            self, cairo_program, cairo_run, n
        ):
            with (
                patch_hint(
                    cairo_program,
                    "memory[ids.output] = res = (int(ids.value) % PRIME) % ids.base\nassert res < ids.bound, f'split_int(): Limb {res} is out of range.'",
                    "memory[ids.output] = (int(ids.value) % PRIME)\n",
                ),
                cairo_error(message="felt_to_bytes_little: byte value is too big"),
            ):
                cairo_run("test__felt_to_bytes_little", n=n)

        # This test checks the function fails if the first bytes is replaced by 0
        # All values that have 0 as first bytes will not raise an error
        # The value 0 is also excluded as it is treated as a special case in the function
        @given(
            n=integers(min_value=1, max_value=2**248 - 1).filter(
                lambda x: int.to_bytes(
                    x, length=(x.bit_length() + 7) // 8, byteorder="little"
                )[0]
                != 0
            )
        )
        def test_should_raise_when_bytes_len_is_not_minimal(
            self, cairo_program, cairo_run, n
        ):
            with (
                patch_hint(
                    cairo_program,
                    "memory[ids.output] = res = (int(ids.value) % PRIME) % ids.base\nassert res < ids.bound, f'split_int(): Limb {res} is out of range.'",
                    f"if ids.value == {n} and ids.bytes_len == 0:\n    memory[ids.output] = 0\nelse:\n    memory[ids.output] = (int(ids.value) % PRIME) % ids.base",
                ),
                cairo_error(message="bytes_len is not the minimal possible"),
            ):
                cairo_run("test__felt_to_bytes_little", n=n)

        def test_should_raise_when_bytes_len_is_greater_than_31(
            self, cairo_program, cairo_run
        ):
            with (
                patch_hint(
                    cairo_program,
                    "memory[ids.output] = res = (int(ids.value) % PRIME) % ids.base\nassert res < ids.bound, f'split_int(): Limb {res} is out of range.'",
                    "memory[ids.output] = 2 if ids.bytes_len < 3 else (int(ids.value) % PRIME) % ids.base\nprint(f'[DEBUG] Byte value: {memory[ids.output]}')",
                ),
                cairo_error(message="bytes_len is not the minimal possible"),
            ):
                cairo_run("test__felt_to_bytes_little", n=3)

    class TestFeltToBytes:
        @given(n=integers(min_value=0, max_value=2**248 - 1))
        def test_should_return_bytes(self, cairo_run, n):
            output = cairo_run("test__felt_to_bytes", n=n)
            res = bytes(output if isinstance(output, list) else [output])
            assert bytes.fromhex(f"{n:x}".rjust(len(res) * 2, "0")) == res

    class TestFeltToBytes20:
        @pytest.mark.parametrize(
            "n", [0, 10, 1234, 0xFFFFFF, 2**128, DEFAULT_PRIME - 1]
        )
        def test_should_return_bytes20(self, cairo_run, n):
            output = cairo_run("test__felt_to_bytes20", n=n)
            assert f"{n:064x}"[-40:] == bytes(output).hex()

    class TestUint256ToBytesLittle:
        @given(n=integers(min_value=0, max_value=2**256 - 1))
        def test_should_return_bytes(self, cairo_run, n):
            output = cairo_run("test__uint256_to_bytes_little", n=int_to_uint256(n))
            res = bytes(output if isinstance(output, list) else [output])
            assert bytes.fromhex(f"{n:x}".rjust(len(res) * 2, "0"))[::-1] == res

    class TestUint256ToBytes:
        @pytest.mark.parametrize(
            "n", [0, 10, 1234, 0xFFFFFF, 2**128, DEFAULT_PRIME - 1, 2**256 - 1]
        )
        def test_should_return_bytes(self, cairo_run, n):
            output = cairo_run("test__uint256_to_bytes", n=int_to_uint256(n))
            res = bytes(output if isinstance(output, list) else [output])
            assert bytes.fromhex(f"{n:x}".rjust(len(res) * 2, "0")) == res

    class TestUint256ToBytes32:
        @given(n=integers(min_value=0, max_value=2**256 - 1))
        def test_should_return_bytes(self, cairo_run, n):
            output = cairo_run("test__uint256_to_bytes32", n=int_to_uint256(n))
            assert bytes.fromhex(f"{n:064x}") == bytes(
                output if isinstance(output, list) else [output]
            )

    class TestBytesToBytes8LittleEndian:

        @given(data=binary(max_size=1000))
        def test_should_return_bytes8(self, cairo_run, data):
            bytes8_little_endian = [
                int.from_bytes(bytes(data[i : i + 8]), "little")
                for i in range(0, len(data), 8)
            ]
            output = cairo_run("test__bytes_to_bytes8_little_endian", bytes=data)

            assert bytes8_little_endian == output

    class TestBytesToFelt:

        @given(data=binary(min_size=0, max_size=35))
        def test_should_convert_bytes_to_felt_with_overflow(self, cairo_run, data):
            output = cairo_run("test__bytes_to_felt", data=list(data))
            assert output == int.from_bytes(data, byteorder="big") % DEFAULT_PRIME
