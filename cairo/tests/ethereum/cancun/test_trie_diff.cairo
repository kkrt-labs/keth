%builtins range_check poseidon

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin

from ethereum.crypto.hash import Hash32
from ethereum_types.bytes import OptionalBytes
from ethereum.cancun.trie_diff import NodeStore, node_store_get, OptionalInternalNode

// Test function that takes an array of node hashes and returns their corresponding nodes
func test_node_store_get{range_check_ptr, poseidon_ptr: PoseidonBuiltin*}(
    node_store: NodeStore, keys: Hash32*, keys_len: felt
) -> OptionalInternalNode* {
    alloc_locals;

    // Allocate array for results
    let (values: OptionalInternalNode*) = alloc();

    // Loop through keys and get values
    _get_values_recursive{node_store=node_store}(keys, values, keys_len, 0);

    return values;
}

// Helper function to recursively process keys and store values
func _get_values_recursive{range_check_ptr, poseidon_ptr: PoseidonBuiltin*, node_store: NodeStore}(
    keys: Hash32*, values: OptionalInternalNode*, n: felt, i: felt
) {
    if (i == n) {
        return ();
    }

    // Get value from node store using the hash directly
    let value = node_store_get(keys[i]);

    // Store result in values array
    assert values[i] = value;

    return _get_values_recursive(keys, values, n, i + 1);
}
