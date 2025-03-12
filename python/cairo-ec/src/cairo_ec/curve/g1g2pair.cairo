from cairo_ec.curve.g1_point import G1Point
from cairo_ec.curve.g2_point import G2Point

// A pair of two points, a G1Point and a G2Point.
// Represent the pair of points of one pairing.
struct G1G2Pair {
    p: G1Point,
    q: G2Point,
}
