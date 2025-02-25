from starkware.cairo.common.cairo_builtins import UInt384
from cairo_core.numeric import bool

struct G1Point {
    x: UInt384,
    y: UInt384,
}

func G1Point__eq__(a: G1Point, b: G1Point) -> bool {
    if (a.x.d0 == b.x.d0 and a.x.d1 == b.x.d1 and a.x.d2 == b.x.d2 and a.x.d3 == b.x.d3 and
        a.y.d0 == b.y.d0 and a.y.d1 == b.y.d1 and a.y.d2 == b.y.d2 and a.y.d3 == b.y.d3) {
        tempvar res = bool(1);
        return res;
    }
    tempvar res = bool(0);
    return res;
}
