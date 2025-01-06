from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.squash_dict import squash_dict

from ethereum_types.numeric import U256
from ethereum_types.bytes import Bytes32

// A Wrapper around dict functions that hashes the key before accessing the dictionary.

func hashdict_bytes32_read{poseidon_ptr: PoseidonBuiltin*, dict_ptr: DictAccess*}(key: Bytes32) -> (
    value: felt
) {
    alloc_locals;
    local value;
    let (hashed_key) = poseidon_hash(key.value.low, key.value.high);
    %{
        dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)
        dict_tracker.current_ptr += ids.DictAccess.SIZE
        preimage = ids.key.value.low + ids.key.value.high * 2**128
        ids.value = dict_tracker.data[preimage.to_bytes(32, "little")]
    %}
    dict_ptr.key = hashed_key;
    dict_ptr.prev_value = value;
    dict_ptr.new_value = value;
    let dict_ptr = dict_ptr + DictAccess.SIZE;
    return (value=value);
}
