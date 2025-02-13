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

// @notice Verifies that a point (x, y) is on the elliptic curve.
// @param x The x coordinate of the point
// @param y The y coordinate of the point
// @param a The a coefficient of the curve
// @param b The b coefficient of the curve
func assert_on_curve(x: felt, y: felt, a: felt, b: felt) {
    tempvar rhs = x * x * x + a * x + b;
    assert y * y = rhs;

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

// @dev Verify that Q = k1*P1 + k2*P2
// It verifies that the equation (3) from the paper
// "Zero Knowledge Proofs of Elliptic Curve Inner Products
// from Principal Divisors and Weil Reciprocity", by Liam Eagen
// (source: https://eprint.iacr.org/2022/596.pdf, p.9) holds.
func ecip_2P(
    div_a_coeff_0: felt,
    div_a_coeff_1: felt,
    div_a_coeff_2: felt,
    div_a_coeff_3: felt,
    div_a_coeff_4: felt,
    div_b_coeff_0: felt,
    div_b_coeff_1: felt,
    div_b_coeff_2: felt,
    div_b_coeff_3: felt,
    div_b_coeff_4: felt,
    div_b_coeff_5: felt,
    div_c_coeff_0: felt,
    div_c_coeff_1: felt,
    div_c_coeff_2: felt,
    div_c_coeff_3: felt,
    div_c_coeff_4: felt,
    div_c_coeff_5: felt,
    div_d_coeff_0: felt,
    div_d_coeff_1: felt,
    div_d_coeff_2: felt,
    div_d_coeff_3: felt,
    div_d_coeff_4: felt,
    div_d_coeff_5: felt,
    div_d_coeff_6: felt,
    div_d_coeff_7: felt,
    div_d_coeff_8: felt,
    x_g: felt,
    y_g: felt,
    x_r: felt,
    y_r: felt,
    ep1_low: felt,
    en1_low: felt,
    sp1_low: felt,
    sn1_low: felt,
    ep2_low: felt,
    en2_low: felt,
    sp2_low: felt,
    sn2_low: felt,
    ep1_high: felt,
    en1_high: felt,
    sp1_high: felt,
    sn1_high: felt,
    ep2_high: felt,
    en2_high: felt,
    sp2_high: felt,
    sn2_high: felt,
    x_q_low: felt,
    y_q_low: felt,
    x_q_high: felt,
    y_q_high: felt,
    x_q_high_shifted: felt,
    y_q_high_shifted: felt,
    x_a0: felt,
    y_a0: felt,
    a: felt,
    b: felt,
    base_rlc: felt,
) {
    // Assert (x_g, y_g) is on curve
    assert y_g * y_g = x_g * x_g * x_g + a * x_g + b;
    // Assert (x_r, y_r) is on curve
    assert y_r * y_r = x_r * x_r * x_r + a + a * x_r + b;
    // Assert (x_a0, y_a0) is on curve
    assert y_a0 * y_a0 = x_a0 * x_a0 * x_a0 + a * x_a0 + b;

    // _slope_intercept_same_point(a0, a)
    // Goal: compute slope intercept of a0 (used in RHS) and coeff0 & coeff2 for LGS
    // Compute slope: m_a0 = (3 * x_a0^2 + a) /2 * y_a0
    tempvar m_a0 = (3 * x_a0 * x_a0 + a) / (2 * y_a0);
    // Compute intercept: b_a0 = y_a0 - x_a0 * m
    tempvar b_a0 = y_a0 - x_a0 * m_a0;
    // Compute a2: a2 = -2*a0
    tempvar x_a2 = m_a0 * m_a0 - 2 * x_a0;
    tempvar y_a2 = -(m_a0 * (x_a0 - x_a2) - y_a0);
    // Compute slope a0 a2: ma0a2 = (y_a2 - y_a0) / (x_a2 - x_a0)
    tempvar m_a0a2 = (y_a2 - y_a0) / (x_a2 - x_a0);
    // Compute coeff2: coeff2 = (2 * y_a2) * (x_a0 - x_a2) / (3 * x_a2^2 + a - 2 * m * y_a2)
    tempvar coeff2 = (2 * y_a2 * (x_a0 - x_a2)) / (3 * x_a2 * x_a2 + a - 2 * m_a0a2 * y_a2);
    // Compute coeff0: coeff0 = coeff2 + 2 * m_a0a2
    tempvar coeff0 = coeff2 + 2 * m_a0a2;

    // Compute LHS = coeff0 * F(a0) - coeff2 * F(a2), with F(x, y) = a(x) + y*b(x)
    // Compute F_a0
    // eval log_div_a_num in x_a0
    tempvar eval_log_div_a_num_x_a0 = div_a_coeff_0 + x_a0 * (
        div_a_coeff_1 + x_a0 * (div_a_coeff_2 + x_a0 * (div_a_coeff_3 + x_a0 * (div_a_coeff_4)))
    );
    // eval log_div_a_den in x_a0
    tempvar eval_log_div_a_den_x_a0 = div_b_coeff_0 + x_a0 * (
        div_b_coeff_1 +
        x_a0 * (
            div_b_coeff_2 + x_a0 * (div_b_coeff_3 + x_a0 * (div_b_coeff_4 + x_a0 * (div_b_coeff_5)))
        )
    );
    // eval log_div_b_num in x_a0
    tempvar eval_log_div_b_num_x_a0 = div_c_coeff_0 + x_a0 * (
        div_c_coeff_1 +
        x_a0 * (
            div_c_coeff_2 + x_a0 * (div_c_coeff_3 + x_a0 * (div_c_coeff_4 + x_a0 * (div_c_coeff_5)))
        )
    );
    // eval log_div_b_den in x_a0
    tempvar eval_log_div_b_den_x_a0 = div_d_coeff_0 + x_a0 * (
        div_d_coeff_1 +
        x_a0 * (
            div_d_coeff_2 +
            x_a0 * (
                div_d_coeff_3 +
                x_a0 * (
                    div_d_coeff_4 +
                    x_a0 * (
                        div_d_coeff_5 +
                        x_a0 * (div_d_coeff_6 + x_a0 * (div_d_coeff_7 + x_a0 * (div_d_coeff_8)))
                    )
                )
            )
        )
    );

    tempvar f_a0 = eval_log_div_a_num_x_a0 / eval_log_div_a_den_x_a0 + y_a0 * eval_log_div_b_num_x_a0 /
        eval_log_div_b_den_x_a0;

    // Compute F_a2
    // eval log_div_a_num in x_a2
    tempvar eval_log_div_a_num_x_a2 = div_a_coeff_0 + x_a2 * (
        div_a_coeff_1 + x_a2 * (div_a_coeff_2 + x_a2 * (div_a_coeff_3 + x_a2 * (div_a_coeff_4)))
    );
    // eval log_div_a_den in x_a2
    tempvar eval_log_div_a_den_x_a2 = div_b_coeff_0 + x_a2 * (
        div_b_coeff_1 +
        x_a2 * (
            div_b_coeff_2 + x_a2 * (div_b_coeff_3 + x_a2 * (div_b_coeff_4 + x_a2 * (div_b_coeff_5)))
        )
    );
    // eval log_div_b_num in x_a2
    tempvar eval_log_div_b_num_x_a2 = div_c_coeff_0 + x_a2 * (
        div_c_coeff_1 +
        x_a2 * (
            div_c_coeff_2 + x_a2 * (div_c_coeff_3 + x_a2 * (div_c_coeff_4 + x_a2 * (div_c_coeff_5)))
        )
    );
    // eval log_div_b_den in x_a2
    tempvar eval_log_div_b_den_x_a2 = div_d_coeff_0 + x_a2 * (
        div_d_coeff_1 +
        x_a2 * (
            div_d_coeff_2 +
            x_a2 * (
                div_d_coeff_3 +
                x_a2 * (
                    div_d_coeff_4 +
                    x_a2 * (
                        div_d_coeff_5 +
                        x_a2 * (div_d_coeff_6 + x_a2 * (div_d_coeff_7 + x_a2 * (div_d_coeff_8)))
                    )
                )
            )
        )
    );

    tempvar f_a2 = eval_log_div_a_num_x_a2 / eval_log_div_a_den_x_a2 + y_a2 * eval_log_div_b_num_x_a2 /
        eval_log_div_b_den_x_a2;

    // Compute LHS
    tempvar lhs = coeff0 * f_a0 - coeff2 * f_a2;

    // Compute RHS: rhs = c0 * base_rhs_low + c1*base_rhs_high + c2*base_rhs_high_shifted
    // compute base_rhs_low
    tempvar base_rhs_low = (x_a0 - x_g) * (
        sp1_low * ep1_low / (y_a0 - (m_a0 * x_g + b_a0)) -
        sn1_low * en1_low / (y_a0 + (m_a0 * x_g + b_a0))
    ) + (x_a0 - x_r) * (
        sp2_low * ep2_low / (y_a0 - (m_a0 * x_r + b_a0)) -
        sn2_low * en2_low / (y_a0 + (m_a0 * x_r + b_a0))
    ) - (x_a0 - x_q_low) / (y_q_low + (m_a0 * x_q_low + b_a0));
    // compute base_rhs_high
    tempvar base_rhs_high = (x_a0 - x_g) * (
        sp1_high * ep1_high / (y_a0 - (m_a0 * x_g + b_a0)) -
        sn1_high * en1_high / (y_a0 + (m_a0 * x_g + b_a0))
    ) + (x_a0 - x_r) * (
        sp2_high * ep2_high / (y_a0 - (m_a0 * x_r + b_a0)) -
        sn2_high * en2_high / (y_a0 + (m_a0 * x_r + b_a0))
    ) - (x_a0 - x_q_high) / (y_q_high + (m_a0 * x_q_high + b_a0));
    // compute base_rhs_high_shifted
    tempvar ep_high_shifted = 5279154705627724249993186093248666011;
    tempvar en_high_shifted = 345561521626566187713367793525016877467;
    tempvar base_rhs_high_shifted = (x_a0 - x_q_high_shifted) * (
        en_high_shifted / (y_a0 + (m_a0 * x_q_high_shifted + b_a0)) -
        ep_high_shifted / (y_a0 - (m_a0 * x_q_high_shifted + b_a0))
    ) - (x_a0 - x_q_high_shifted) / (y_q_high_shifted + (m_a0 * x_q_high_shifted + b_a0));
    // Compute c0: base_rlc
    // Compute c1: base_rlc^2
    tempvar c1 = base_rlc * base_rlc;
    // Compute c2: base_rlc^3
    tempvar c2 = c1 * base_rlc;

    tempvar rhs = base_rlc * base_rhs_low + c1 * base_rhs_high + c2 * base_rhs_high_shifted;

    // Assert that RHS - LHZ == 0

    assert lhs = rhs;

    return ();

    end:
}
