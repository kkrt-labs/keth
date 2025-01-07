from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from starkware.cairo.common.builtin_poseidon.poseidon import poseidon_hash
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.uint256 import Uint256

from ethereum_types.numeric import U256
from ethereum_types.bytes import Bytes32
from ethereum.cancun.fork_types import Address

from src.utils.maths import unsigned_div_rem

func dict_copy{range_check_ptr}(dict_start: DictAccess*, dict_end: DictAccess*) -> (
    DictAccess*, DictAccess*
) {
    alloc_locals;
    let (local new_start: DictAccess*) = alloc();
    tempvar new_end = new_start + (dict_end - dict_start);
    memcpy(new_start, dict_start, dict_end - dict_start);
    // Register the segment as a dict in the DictManager.
    %{ dict_copy %}
    return (new_start, new_end);
}

// @dev Copied from the standard library with an updated dict_new() implementation.
func dict_squash{range_check_ptr}(
    dict_accesses_start: DictAccess*, dict_accesses_end: DictAccess*
) -> (squashed_dict_start: DictAccess*, squashed_dict_end: DictAccess*) {
    alloc_locals;

    %{ dict_squash %}
    ap += 1;
    let squashed_dict_start = cast([ap - 1], DictAccess*);

    let (squashed_dict_end) = squash_dict(
        dict_accesses=dict_accesses_start,
        dict_accesses_end=dict_accesses_end,
        squashed_dict=squashed_dict_start,
    );

    %{
        # Update the DictTracker's current_ptr to point to the end of the squashed dict.
        __dict_manager.get_tracker(ids.squashed_dict_start).current_ptr = \
            ids.squashed_dict_end.address_
    %}
    return (squashed_dict_start=squashed_dict_start, squashed_dict_end=squashed_dict_end);
}

// A wrapper around dict_read that hashes the key before accessing the dictionary.
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

// A wrapper around dict_read that converts the key to a 20-byte address before accessing the dictionary.
func dict_address_read{dict_ptr: DictAccess*}(key: Address) -> (value: felt) {
    alloc_locals;
    local value;
    %{
        dict_tracker = __dict_manager.get_tracker(ids.dict_ptr)
        dict_tracker.current_ptr += ids.DictAccess.SIZE
        ids.value = dict_tracker.data[ids.key.value.to_bytes(20, "little")]
    %}
    dict_ptr.key = key.value;
    dict_ptr.prev_value = value;
    dict_ptr.new_value = value;
    let dict_ptr = dict_ptr + DictAccess.SIZE;
    return (value=value);
}
