from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.math import assert_le

func main{syscall_ptr: felt*, pedersen_ptr: HashBuiltin*, range_check_ptr}() {
    alloc_locals;
    local x = 5;
    assert_le(x, 10);
    let y = alloc();
    return ();
}
