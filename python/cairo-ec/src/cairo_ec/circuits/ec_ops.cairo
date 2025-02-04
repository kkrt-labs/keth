// @dev Add two distinct EC points, doesn't make any checks on the inputs.
func ec_add(x0: felt, y0: felt, x1: felt, y1: felt) -> (felt, felt) {
    tempvar l = (y1 - y0) / (x1 - x0);

    tempvar x = l * l - x0 - x1;
    tempvar y = l * (x0 - x) - y0;

    return (x, y);

    end:
}

// @dev Double an EC point, doesn't make any checks on the inputs.
func ec_double(x0: felt, y0: felt, a: felt) -> (felt, felt) {
    tempvar l = (3 * x0 * x0 + a) / (2 * y0);

    tempvar x = l * l - x0 - x0;
    tempvar y = l * (x0 - x) - y0;

    return (x, y);

    end:
}

// @dev Assert that a point is on the curve.
func assert_on_curve(x: felt, y: felt, a: felt, b: felt) {
    assert y * y = (x * x * x + a * x + b);

    return ();

    end:
}

// @dev Assert that a point is not on the curve.
// @dev If the point is on the curve, diff = 0 and 1 / diff will fail.
func assert_not_on_curve(x: felt, y: felt, a: felt, b: felt) -> felt {
    tempvar diff = y * y - (x * x * x + a * x + b);

    return 1 / diff;

    end:
}
