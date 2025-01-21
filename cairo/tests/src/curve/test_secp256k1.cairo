from starkware.cairo.common.cairo_builtins import UInt384
from src.curve.secp256k1 import get_generator_point

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
