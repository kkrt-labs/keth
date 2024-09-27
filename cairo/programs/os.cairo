%builtins pedersen output

from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.cairo_builtins import HashBuiltin

from src.model import model

func main{pedersen_ptr: HashBuiltin*, output_ptr: felt*}() {
    %{ dict_manager %}
    tempvar block: model.Block*;
    tempvar initial_state: model.State*;
    %{ block %}
    // TODO: Compute initial state root hash and compare with block.parent_hash
    // TODO: Loop through transactions and apply them to the initial state
    // TODO: Compute the state root hash after applying all transactions
    // TODO: Compare the final state root hash with block.state_root
    return ();
}
