%builtins output

from starkware.cairo.common.memcpy import memcpy

from src.model import model

func main{output_ptr: felt*}() {
    tempvar block: model.Block*;
    %{ block %}

    return ();
}
