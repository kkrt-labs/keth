from ethereum.rlp import encode_bytes, get_joined_encodings, encode_sequence, rlp_hash
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from ethereum.base_types import Bytes, TupleBytes
from ethereum.crypto.hash import Hash32

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

func test_rlp_hash{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    ) -> Hash32 {
    tempvar raw_bytes: Bytes;
    %{ memory[ap - 1] = gen_arg(program_input["raw_bytes"]) %}
    let hash = rlp_hash(raw_bytes);
    return hash;
}
