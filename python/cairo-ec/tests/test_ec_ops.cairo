from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import ModBuiltin, PoseidonBuiltin, UInt384
from starkware.cairo.common.uint256 import Uint256

from cairo_ec.ec_ops import ec_add, ec_mul, try_get_point_from_x, get_random_point
from cairo_ec.curve.g1_point import G1Point
from cairo_core.numeric import U384

func test__try_get_point_from_x{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: U384, v: felt, a: U384, b: U384, g: U384, p: U384) -> (y: U384, is_on_curve: felt) {
    alloc_locals;

    let (y, is_on_curve) = try_get_point_from_x(x=x, v=v, a=a, b=b, g=g, p=p);
    return (y, is_on_curve);
}

func test__get_random_point{
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(seed: felt, a: U384, b: U384, g: U384, p: U384) -> G1Point {
    alloc_locals;

    let point = get_random_point(seed, a, b, g, p);

    return point;
}

func test__ec_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    p: G1Point, q: G1Point, a: U384, modulus: U384
) -> G1Point {
    alloc_locals;

    let res = ec_add(p, q, a, modulus);
    return res;
}

func test__ec_mul{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(p: G1Point, k: U384, modulus: U384) -> G1Point {
    alloc_locals;
    let res = ec_mul(p, k, modulus);
    return res;
}
