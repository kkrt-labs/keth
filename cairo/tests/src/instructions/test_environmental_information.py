import random

import pytest
from Crypto.Hash import keccak
from hypothesis import example, given, settings
from hypothesis import strategies as st

EXISTING_ACCOUNT = 0xABDE1
EXISTING_ACCOUNT_SN_ADDR = 0x1234
NON_EXISTING_ACCOUNT = 0xDEAD

pytestmark = pytest.mark.python_vm


@pytest.fixture(scope="module", params=[0, 32], ids=["no bytecode", "32 bytes"])
def bytecode(request):
    return [random.randint(0, 255) for _ in range(request.param)]


@pytest.fixture(scope="module")
def bytecode_hash(bytecode):
    keccak_hash = keccak.new(digest_bits=256)
    keccak_hash.update(bytearray(bytecode))
    return int.from_bytes(keccak_hash.digest(), byteorder="big")


@pytest.fixture(
    scope="module",
    params=[EXISTING_ACCOUNT, NON_EXISTING_ACCOUNT],
    ids=["existing", "non existing"],
)
def address(request):
    return request.param


class TestEnvironmentalInformation:
    class TestAddress:
        def test_should_push_address(self, cairo_run):
            cairo_run("test__exec_address__should_push_address_to_stack")

    class TestCopy:
        @pytest.mark.parametrize("opcode_number", [0x39, 0x37])
        @pytest.mark.parametrize(
            "size, offset, dest_offset",
            [(31, 0, 0), (33, 0, 0), (1, 32, 0)],
            ids=[
                "size_is_bytecodelen-1",
                "size_is_bytecodelen+1",
                "offset_is_bytecodelen",
            ],
        )
        def test_exec_copy_should_copy_code(
            self, cairo_run, size, offset, dest_offset, opcode_number, bytecode
        ):
            bytecode.insert(0, opcode_number)  # random bytecode that can be mutated
            (_, memory) = cairo_run(
                "test__exec_copy",
                size=size,
                offset=offset,
                dest_offset=dest_offset,
                bytecode=bytecode,
                opcode_number=opcode_number,
            )

            copied_bytecode = bytes(
                # bytecode is padded with surely enough 0 and then sliced
                (bytecode + [0] * (offset + size))[offset : offset + size]
            )
            assert (
                bytes.fromhex(memory)[dest_offset : dest_offset + size]
                == copied_bytecode
            )

        @pytest.mark.slow
        @settings(max_examples=20)  # for max_examples=2, it takes 45.71s in local
        @given(
            opcode_number=st.sampled_from([0x39, 0x37]),
            offset=st.integers(0, 2**128 - 1),
            dest_offset=st.integers(0, 2**128 - 1),
        )
        @example(opcode_number=0x39, offset=2**128 - 1, dest_offset=0)
        @example(opcode_number=0x39, offset=0, dest_offset=2**128 - 1)
        @example(opcode_number=0x37, offset=2**128 - 1, dest_offset=0)
        @example(opcode_number=0x37, offset=0, dest_offset=2**128 - 1)
        def test_exec_copy_fail_oog(
            self, cairo_run, opcode_number, bytecode, offset, dest_offset
        ):
            bytecode.insert(0, opcode_number)  # random bytecode that can be mutated
            (evm, _) = cairo_run(
                "test__exec_copy",
                size=2**128 - 1,
                offset=offset,
                dest_offset=dest_offset,
                bytecode=bytecode,
                opcode_number=opcode_number,
            )
            assert evm["reverted"] == 2
            assert b"Kakarot: outOfGas left" in bytes(evm["return_data"])

        @pytest.mark.parametrize("opcode_number", [0x39, 0x37])
        @pytest.mark.parametrize(
            "size",
            [31, 32, 33, 0],
            ids=[
                "size_is_bytecodelen-1",
                "size_is_bytecodelen",
                "size_is_bytecodelen+1",
                "size_is_0",
            ],
        )
        def test_exec_copy_offset_high_zellic_issue_1258(
            self, cairo_run, size, opcode_number, bytecode
        ):
            bytecode.insert(0, opcode_number)  # random bytecode that can be mutated
            offset_high = 1
            memory = cairo_run(
                "test__exec_copy_offset_high_zellic_issue_1258",
                size=size,
                offset_high=offset_high,
                dest_offset=0,
                bytecode=bytecode,
                opcode_number=opcode_number,
            )
            # with a offset_high != 0 all copied bytes are 0
            copied_bytecode = bytes([0] * size)
            assert bytes.fromhex(memory)[0:size] == copied_bytecode

    class TestGasPrice:
        def test_gasprice(self, cairo_run):
            cairo_run("test__exec_gasprice")
