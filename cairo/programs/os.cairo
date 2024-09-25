%builtins output

from starkware.cairo.common.memcpy import memcpy

from src.model import model

func main{output_ptr: felt*}() {
    tempvar block_header: model.BlockHeader*;
    %{ block_header %}

    return ();
}
