%builtins output pedersen

from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.cairo_builtins import HashBuiltin

from src.model import model

func get_block() ->  model.Block* {
    tempvar block = cast(nondet %{ segments.add() %}, model.Block*);
    %{ block %}
    return block;
}

func main{output_ptr: felt*, pedersen_ptr: HashBuiltin*}() {
    let block = get_block();
    return ();
}
