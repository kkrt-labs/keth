from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin
from starkware.cairo.common.alloc import alloc

from src.curve.secp256k1 import get_generator_point, try_get_point_from_x
from src.curve.g1_point import G1Point

func test__get_generator_point() {
    let generator = get_generator_point();

    assert generator.x.d0 = 0x2dce28d959f2815b16f81798;
    assert generator.x.d1 = 0x55a06295ce870b07029bfcdb;
    assert generator.x.d2 = 0x79be667ef9dcbbac;
    assert generator.x.d3 = 0x0;
    assert generator.y.d0 = 0xa68554199c47d08ffb10d4b8;
    assert generator.y.d1 = 0x5da4fbfc0e1108a8fd17b448;
    assert generator.y.d2 = 0x483ada7726a3c465;
    assert generator.y.d3 = 0x0;

    return ();
}

func test__try_get_point_from_x{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}() -> (y: UInt384*, is_on_curve: felt) {
    alloc_locals;
    let (x_ptr) = alloc();
    tempvar v;
    %{
        segments.write_arg(ids.x_ptr, program_input["x"])
        ids.v = program_input["v"]
    %}

    let x = [cast(x_ptr, UInt384*)];
    let (y, is_on_curve) = try_get_point_from_x(x=x, v=v);
    // serde doesn't handle non pointer types in tuples
    tempvar y_ptr = new UInt384(y.d0, y.d1, y.d2, y.d3);
    return (y_ptr, is_on_curve);
}
