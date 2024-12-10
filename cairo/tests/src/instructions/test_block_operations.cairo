from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.uint256 import Uint256, assert_uint256_eq
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.uint256 import ALL_ONES

from src.instructions.block_information import BlockInformation
from src.memory import Memory
from src.model import model
from src.stack import Stack
from src.state import State
from tests.utils.helpers import TestHelpers
from src.utils.utils import Helpers

func test__exec_blob_base_fee{
    pedersen_ptr: HashBuiltin*,
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
}() -> model.Stack* {
    alloc_locals;
    %{ dict_manager %}
    local block: model.Block*;
    local state: model.State*;
    %{ block %}
    %{ state %}
    // Given
    let stack = Stack.init();
    let memory = Memory.init();
    let (bytecode) = alloc();
    assert [bytecode] = 0x4a;  // BLOBBASEFEE
    let address = 0xdead;
    let (calldata) = alloc();
    let evm = TestHelpers.init_evm_from_with_block_header(
        0, bytecode, address, 0, calldata, block.block_header
    );

    with stack, memory, state {
        BlockInformation.exec_block_information(evm);
    }

    return stack;
}
