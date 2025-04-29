from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.alloc import alloc
from ethereum.crypto.hash import Hash32, blake2s_bytes
from cairo_core.bytes import Bytes, Bytes20, Bytes32, TupleBytes32, Bytes256, BytesStruct, Bytes8
from cairo_core.hash.blake2s import blake2s_add_felt, blake2s, blake2s_add_uint256

func Bytes__hash__{range_check_ptr}(self: Bytes) -> Hash32 {
    return blake2s_bytes(self);
}

func Bytes8__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(self: Bytes8) -> Hash32 {
    alloc_locals;
    let (data) = alloc();
    let data_start = data;
    blake2s_add_felt{data=data}(self.value, bigend=0);
    let (res_u256) = blake2s(data_start, 8);
    tempvar hash = Hash32(value=new res_u256);
    return hash;
}

func Bytes20__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(self: Bytes20) -> Hash32 {
    alloc_locals;
    let (data) = alloc();
    let data_start = data;
    blake2s_add_felt{data=data}(self.value, bigend=0);
    let (res_u256) = blake2s(data_start, 20);
    tempvar hash = Hash32(value=new res_u256);
    return hash;
}

func Bytes32__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(self: Bytes32) -> Hash32 {
    let (data) = alloc();
    let data_start = data;
    blake2s_add_uint256{data=data}([self.value]);
    let (res_u256) = blake2s(data_start, 32);
    tempvar hash = Hash32(value=new res_u256);
    return hash;
}

func Bytes256__hash__{range_check_ptr}(self: Bytes256) -> Hash32 {
    tempvar bytes = Bytes(new BytesStruct(data=self.value, len=256));
    return blake2s_bytes(bytes);
}

func TupleBytes32__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    self: TupleBytes32
) -> Hash32 {
    alloc_locals;
    let (acc) = alloc();
    let acc_start = acc;
    let index = 0;
    _innerTupleBytes32__hash__{acc=acc, index=index}(self);

    let n_bytes = 32 * self.value.len;
    let (res) = blake2s(data=acc_start, n_bytes=n_bytes);
    tempvar hash = Hash32(value=new res);
    return hash;
}

func _innerTupleBytes32__hash__{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, acc: felt*, index: felt
}(self: TupleBytes32) {
    if (index == self.value.len) {
        return ();
    }

    let item = self.value.data[index];
    let item_hash = Bytes32__hash__(item);
    blake2s_add_uint256{data=acc}([item_hash.value]);
    let index = index + 1;
    return _innerTupleBytes32__hash__(self);
}
