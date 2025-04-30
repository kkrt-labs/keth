from cairo_core.numeric import bool, U384, U384Struct

// A G1Point is a point on an elliptic curve over a field Fp.
// Affine coordinates representation.
struct G1Point {
    value: G1PointStruct*,
}

struct G1PointStruct {
    x: U384,
    y: U384,
}

func G1Point__eq__(a: G1Point, b: G1Point) -> bool {
    if (a.value.x.value.d0 == b.value.x.value.d0 and a.value.x.value.d1 == b.value.x.value.d1 and
        a.value.x.value.d2 == b.value.x.value.d2 and a.value.x.value.d3 == b.value.x.value.d3 and
        a.value.y.value.d0 == b.value.y.value.d0 and a.value.y.value.d1 == b.value.y.value.d1 and
        a.value.y.value.d2 == b.value.y.value.d2 and a.value.y.value.d3 == b.value.y.value.d3) {
        tempvar res = bool(1);
        return res;
    }
    tempvar res = bool(0);
    return res;
}

func G1Point_zero() -> G1Point {
    tempvar res = G1Point(
        new G1PointStruct(U384(new U384Struct(0, 0, 0, 0)), U384(new U384Struct(0, 0, 0, 0)))
    );
    return res;
}
