from ethereum.rlp import encode_bytes
from ethereum.base_types import Bytes

func test_encode_bytes{range_check_ptr}() -> Bytes {
    tempvar raw_bytes: Bytes;
    %{ memory[ap - 1] = gen_arg(program_input["raw_bytes"]) %}
    let encoded_bytes = encode_bytes(raw_bytes);
    return encoded_bytes;
}
