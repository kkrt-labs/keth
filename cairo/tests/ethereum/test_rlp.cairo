from ethereum.rlp import (
    encode_bytes,
    get_joined_encodings,
    encode_sequence,
    rlp_hash,
    decode_to_bytes,
)
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from ethereum.base_types import Bytes, TupleBytes
from ethereum.crypto.hash import Hash32

func test_encode_bytes{range_check_ptr}(raw_bytes: Bytes) -> Bytes {
    let encoded_bytes = encode_bytes(raw_bytes);
    return encoded_bytes;
}

func test_get_joined_encodings{range_check_ptr}(raw_sequence: TupleBytes) -> Bytes {
    let encoded_bytes = get_joined_encodings(raw_sequence);
    return encoded_bytes;
}

func test_encode_sequence{range_check_ptr}(raw_sequence: TupleBytes) -> Bytes {
    let encoded_bytes = encode_sequence(raw_sequence);
    return encoded_bytes;
}

func test_rlp_hash{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*}(
    raw_bytes: Bytes
) -> Hash32 {
    let hash = rlp_hash(raw_bytes);
    return hash;
}

func test_decode_to_bytes{range_check_ptr}(encoded_bytes: Bytes) -> Bytes {
    let decoded_bytes = decode_to_bytes(encoded_bytes);
    return decoded_bytes;
}
