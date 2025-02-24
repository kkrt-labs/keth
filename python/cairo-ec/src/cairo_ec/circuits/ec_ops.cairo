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

// @dev Assert that a point is, or is not, on the curve by checking that either y is actually the square root of rhs
//      (is_on_curve = True => y^2 = rhs) or y is the square root of rhs * g (is_on_curve = False => y^2 = rhs * g),
//      which mean that rhs is not a quadratic residue because g * rhs is, and so that x is not on the curve.
// @param x The x coordinate of the point
// @param y The y coordinate of the point
// @param g The generator point
// @param is_on_curve True if the point is on the curve, False otherwise
func assert_is_on_curve(x: felt, y: felt, a: felt, b: felt, g: felt, is_on_curve: felt) {
    assert is_on_curve * (1 - is_on_curve) = 0;
    tempvar rhs = x * x * x + a * x + b;
    assert y * y = rhs * is_on_curve + g * rhs * (1 - is_on_curve);

    return ();

    end:
}

// @notice Asserts that a point is not on the curve by checking that either y is not the square root
// of rhs.  The check is done by returning 1 / (y^2 - rhs), which is 0 if y^2 = rhs and would panic.
// @param x The x coordinate of the point
// @param y The y coordinate of the point
// @param a The a coefficient of the curve
// @param b The b coefficient of the curve
func assert_not_on_curve(x: felt, y: felt, a: felt, b: felt) -> felt {
    tempvar rhs = x * x * x + a * x + b;
    // Fails if y^2 = rhs
    return 1 / (y * y - rhs);

    end:
}
