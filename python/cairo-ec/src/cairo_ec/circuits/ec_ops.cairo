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

// @notice Verifies that a point (x, y) satisfies a specific elliptic curve condition based on is_on_curve.
// @dev If is_on_curve = 1, asserts y^2 = x^3 + ax + b, confirming the point is on the curve.
//      If is_on_curve = 0, asserts y^2 = g * (x^3 + ax + b), verifying that no `y` satisfies the curve equation for the given `x`.
//      Use this when you need to prove a point meets one of these equations, not to fail on invalid points.
//      For explicit rejection of on-curve points, see assert_not_on_curve.
// @param x The x coordinate of the point
// @param y The y coordinate of the point
// @param a The a coefficient of the curve
// @param b The b coefficient of the curve
// @param g A scalar used when is_on_curve = 0
// @param is_on_curve Flag (0 or 1) indicating which condition to verify
func assert_x_is_on_curve(x: felt, y: felt, a: felt, b: felt, g: felt, is_on_curve: felt) {
    assert is_on_curve * (1 - is_on_curve) = 0;  // Ensures is_on_curve is boolean (0 or 1)
    tempvar rhs = x * x * x + a * x + b;
    assert y * y = rhs * is_on_curve + g * rhs * (1 - is_on_curve);

    return ();

    end:
}

// @notice Asserts that a point (x, y) is not on the elliptic curve by failing if y^2 = x^3 + ax + b.
// @dev Computes rhs = x^3 + ax + b and returns 1 / (y^2 - rhs). This succeeds if the point is off the curve
//      (y^2 ≠ rhs) and fails (division by zero) if the point is on the curve (y^2 = rhs).
//      Use this to explicitly reject points that are on the curve when they shouldn’t be (e.g., invalid inputs).
//      Unlike assert_x_is_on_curve with is_on_curve = 0, this forces failure for on-curve points.
// @param x The x coordinate of the point
// @param y The y coordinate of the point
// @param a The a coefficient of the curve
// @param b The b coefficient of the curve
// @return felt A value (1 / (y^2 - rhs)) if the point is off the curve; fails otherwise
func assert_not_on_curve(x: felt, y: felt, a: felt, b: felt) -> felt {
    tempvar rhs = x * x * x + a * x + b;
    // Fails if y^2 = rhs (point is on the curve)
    return 1 / (y * y - rhs);

    end:
}
