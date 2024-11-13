from ethereum.rlp import encode_bytes, get_joined_encodings, encode_sequence
from ethereum.base_types import Bytes, TupleBytes

func test_encode_bytes{range_check_ptr}() -> Bytes {
    tempvar raw_bytes: Bytes;
    %{ memory[ap - 1] = gen_arg(program_input["raw_bytes"]) %}
    let encoded_bytes = encode_bytes(raw_bytes);
    return encoded_bytes;
}

func test_get_joined_encodings{range_check_ptr}() -> Bytes {
    tempvar raw_sequence: TupleBytes;
    %{ memory[ap - 1] = gen_arg(program_input["raw_sequence"]) %}
    let encoded_bytes = get_joined_encodings(raw_sequence);
    return encoded_bytes;
}

func test_encode_sequence{range_check_ptr}() -> Bytes {
    tempvar raw_sequence: TupleBytes;
    %{ memory[ap - 1] = gen_arg(program_input["raw_sequence"]) %}
    let encoded_bytes = encode_sequence(raw_sequence);
    return encoded_bytes;
}
