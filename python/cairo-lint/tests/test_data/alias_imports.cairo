from starkware.cairo.common.math import assert_nn as check_non_negative
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin as Bitwise,
    HashBuiltin,
    SignatureBuiltin as Sig,
)
from starkware.cairo.common.uint256 import Uint256, uint256_add as add256, uint256_sub

func main{bitwise_ptr: Bitwise*, sig_ptr: Sig*}(start: Uint256) {
    alloc();  // Use alloc directly

    // Use aliased imports
    let bitwise: Bitwise* = bitwise_ptr;
    let sig: Sig* = sig_ptr;

    // Use original import
    let value: Uint256 = start;

    // Use check_non_negative (alias for assert_nn)
    check_non_negative(value.low);

    return ();
}
