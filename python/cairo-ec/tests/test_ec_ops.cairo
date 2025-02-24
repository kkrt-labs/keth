from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import ModBuiltin, PoseidonBuiltin, UInt384
from starkware.cairo.common.uint256 import Uint256

from cairo_ec.ec_ops import ec_add, try_get_point_from_x, get_random_point
from cairo_ec.curve.g1_point import G1Point

func test__try_get_point_from_x{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}() -> (y: UInt384*, is_on_curve: felt) {
    alloc_locals;
    let (x_ptr: UInt384*) = alloc();
    tempvar v;
    let (a_ptr: UInt384*) = alloc();
    let (b_ptr: UInt384*) = alloc();
    let (g_ptr: UInt384*) = alloc();
    let (p_ptr: UInt384*) = alloc();
    %{
        segments.write_arg(ids.x_ptr.address_, program_input["x"])
        ids.v = program_input["v"]
        segments.write_arg(ids.a_ptr.address_, program_input["a"])
        segments.write_arg(ids.b_ptr.address_, program_input["b"])
        segments.write_arg(ids.g_ptr.address_, program_input["g"])
        segments.write_arg(ids.p_ptr.address_, program_input["p"])
    %}

    let (y, is_on_curve) = try_get_point_from_x(x=x_ptr, v=v, a=a_ptr, b=b_ptr, g=g_ptr, p=p_ptr);
    // serde doesn't handle non pointer types in tuples
    tempvar y_ptr = new UInt384(y.d0, y.d1, y.d2, y.d3);
    return (y_ptr, is_on_curve);
}

func test__get_random_point{
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}() -> G1Point* {
    alloc_locals;
    tempvar seed;
    let (a_ptr: UInt384*) = alloc();
    let (b_ptr: UInt384*) = alloc();
    let (g_ptr: UInt384*) = alloc();
    let (p_ptr: UInt384*) = alloc();
    %{
        ids.seed =  program_input["seed"]
        segments.write_arg(ids.a_ptr.address_, program_input["a"])
        segments.write_arg(ids.b_ptr.address_, program_input["b"])
        segments.write_arg(ids.g_ptr.address_, program_input["g"])
        segments.write_arg(ids.p_ptr.address_, program_input["p"])
    %}

    let point = get_random_point(seed, a_ptr, b_ptr, g_ptr, p_ptr);

    tempvar point_ptr = new G1Point(
        UInt384(point.x.d0, point.x.d1, point.x.d2, point.x.d3),
        UInt384(point.y.d0, point.y.d1, point.y.d2, point.y.d3),
    );
    return point_ptr;
}

func test__ec_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    ) -> G1Point* {
    alloc_locals;
    let (p_ptr: G1Point*) = alloc();
    let (q_ptr: G1Point*) = alloc();
    let (a_ptr: UInt384*) = alloc();
    let (modulus_ptr: UInt384*) = alloc();
    %{
        segments.write_arg(ids.p_ptr.address_, program_input["p"])
        segments.write_arg(ids.q_ptr.address_, program_input["q"])
        segments.write_arg(ids.a_ptr.address_, program_input["a"])
        segments.write_arg(ids.modulus_ptr.address_, program_input["modulus"])
    %}

    let res = ec_add([p_ptr], [q_ptr], [a_ptr], [modulus_ptr]);

    tempvar res_ptr = new G1Point(
        UInt384(res.x.d0, res.x.d1, res.x.d2, res.x.d3),
        UInt384(res.y.d0, res.y.d1, res.y.d2, res.y.d3),
    );
    return res_ptr;
}
