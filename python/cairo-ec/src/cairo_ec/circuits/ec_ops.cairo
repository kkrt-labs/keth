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
func ecip_2p(
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
    g_x: felt,
    g_y: felt,
    r_x: felt,
    r_y: felt,
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
    q_low_x: felt,
    q_low_y: felt,
    q_high_x: felt,
    q_high_y: felt,
    q_high_shifted_x: felt,
    q_high_shifted_y: felt,
    a0_x: felt,
    a0_y: felt,
    a: felt,
    b: felt,
    base_rlc: felt,
) {
    // Assert (g_x, g_y) is on curve
    assert g_y * g_y = g_x * g_x * g_x + a * g_x + b;
    // Assert (r_x, r_y) is on curve
    assert r_y * r_y = r_x * r_x * r_x + a + a * r_x + b;
    // Assert (a0_x, a0_y) is on curve
    assert a0_y * a0_y = a0_x * a0_x * a0_x + a * a0_x + b;
    // Assert (q_low_x, q_low_y) is on curve
    assert q_low_y * q_low_y = q_low_x * q_low_x * q_low_x + a * q_low_x + b;
    // Assert (q_high_x, q_high_y) is on curve
    assert q_high_y * q_high_y = q_high_x * q_high_x * q_high_x + a * q_high_x + b;
    // Assert (q_high_shifted_x, q_high_shifted_y) is on curve
    assert q_high_shifted_y * q_high_shifted_y = q_high_shifted_x * q_high_shifted_x *
        q_high_shifted_x + a * q_high_shifted_x + b;

    // slope a0
    tempvar m_a0 = (3 * a0_x * a0_x + a) / (2 * a0_y);
    // intercept a0
    tempvar b_a0 = a0_y - a0_x * m_a0;
    tempvar x_a2 = m_a0 * m_a0 - 2 * a0_x;
    tempvar y_a2 = 0 - (m_a0 * (a0_x - x_a2) - a0_y);
    // Slope a0, a2
    tempvar m_a0a2 = (y_a2 - a0_y) / (x_a2 - a0_x);
    tempvar coeff2 = (2 * y_a2 * (a0_x - x_a2)) / (3 * x_a2 * x_a2 + a - 2 * m_a0a2 * y_a2);
    tempvar coeff0 = coeff2 + 2 * m_a0a2;

    // LHS = coeff0 * f(a0) - coeff2 * f(a2), with f(x, y) = a(x) + y*b(x)
    // f(a0)
    tempvar eval_log_div_a_num_a0_x = div_a_coeff_0 + a0_x * (
        div_a_coeff_1 + a0_x * (div_a_coeff_2 + a0_x * (div_a_coeff_3 + a0_x * div_a_coeff_4))
    );
    tempvar eval_log_div_a_den_a0_x = div_b_coeff_0 + a0_x * (
        div_b_coeff_1 +
        a0_x * (
            div_b_coeff_2 + a0_x * (div_b_coeff_3 + a0_x * (div_b_coeff_4 + a0_x * div_b_coeff_5))
        )
    );
    tempvar eval_log_div_b_num_a0_x = div_c_coeff_0 + a0_x * (
        div_c_coeff_1 +
        a0_x * (
            div_c_coeff_2 + a0_x * (div_c_coeff_3 + a0_x * (div_c_coeff_4 + a0_x * div_c_coeff_5))
        )
    );
    tempvar eval_log_div_b_den_a0_x = div_d_coeff_0 + a0_x * (
        div_d_coeff_1 +
        a0_x * (
            div_d_coeff_2 +
            a0_x * (
                div_d_coeff_3 +
                a0_x * (
                    div_d_coeff_4 +
                    a0_x * (
                        div_d_coeff_5 +
                        a0_x * (div_d_coeff_6 + a0_x * (div_d_coeff_7 + a0_x * div_d_coeff_8))
                    )
                )
            )
        )
    );

    tempvar f_a0 = eval_log_div_a_num_a0_x / eval_log_div_a_den_a0_x + a0_y *
        eval_log_div_b_num_a0_x / eval_log_div_b_den_a0_x;

    // f(a2)
    tempvar eval_log_div_a_num_x_a2 = div_a_coeff_0 + x_a2 * (
        div_a_coeff_1 + x_a2 * (div_a_coeff_2 + x_a2 * (div_a_coeff_3 + x_a2 * div_a_coeff_4))
    );
    tempvar eval_log_div_a_den_x_a2 = div_b_coeff_0 + x_a2 * (
        div_b_coeff_1 +
        x_a2 * (
            div_b_coeff_2 + x_a2 * (div_b_coeff_3 + x_a2 * (div_b_coeff_4 + x_a2 * div_b_coeff_5))
        )
    );
    tempvar eval_log_div_b_num_x_a2 = div_c_coeff_0 + x_a2 * (
        div_c_coeff_1 +
        x_a2 * (
            div_c_coeff_2 + x_a2 * (div_c_coeff_3 + x_a2 * (div_c_coeff_4 + x_a2 * div_c_coeff_5))
        )
    );
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
                        x_a2 * (div_d_coeff_6 + x_a2 * (div_d_coeff_7 + x_a2 * div_d_coeff_8))
                    )
                )
            )
        )
    );
    tempvar f_a2 = eval_log_div_a_num_x_a2 / eval_log_div_a_den_x_a2 + y_a2 *
        eval_log_div_b_num_x_a2 / eval_log_div_b_den_x_a2;

    // Compute LHS
    tempvar lhs = coeff0 * f_a0 - coeff2 * f_a2;

    // base_rhs_low
    tempvar num_g = a0_x - g_x;
    tempvar den_tmp_g = m_a0 * g_x + b_a0;
    tempvar den_pos_g = g_y - den_tmp_g;
    tempvar den_neg_g = (0 - g_y) - den_tmp_g;
    tempvar eval_pos_low_g = sp1_low * ep1_low * num_g / den_pos_g;
    tempvar eval_neg_low_g = sn1_low * en1_low * num_g / den_neg_g;
    tempvar eval_low_g = eval_pos_low_g + eval_neg_low_g;

    tempvar num_r = a0_x - r_x;
    tempvar den_tmp_r = m_a0 * r_x + b_a0;
    tempvar den_pos_r = r_y - den_tmp_r;
    tempvar den_neg_r = (0 - r_y) - den_tmp_r;
    tempvar eval_pos_low_r = sp2_low * ep2_low * num_r / den_pos_r;
    tempvar eval_neg_low_r = sn2_low * en2_low * num_r / den_neg_r;
    tempvar eval_low_r = eval_pos_low_r + eval_neg_low_r;

    tempvar num_q_low = a0_x - q_low_x;
    tempvar den_tmp_q_low = m_a0 * q_low_x + b_a0;
    tempvar den_neg_q_low = (0 - q_low_y) - den_tmp_q_low;
    tempvar eval_q_low = num_q_low / den_neg_q_low;

    tempvar rhs_low = eval_low_g + eval_low_r + eval_q_low;

    // base_rhs_high
    tempvar eval_pos_high_g = sp1_high * ep1_high * num_g / den_pos_g;
    tempvar eval_neg_high_g = sn1_high * en1_high * num_g / den_neg_g;
    tempvar eval_high_g = eval_pos_high_g + eval_neg_high_g;

    tempvar eval_pos_high_r = sp2_high * ep2_high * num_r / den_pos_r;
    tempvar eval_neg_high_r = sn2_high * en2_high * num_r / den_neg_r;
    tempvar eval_high_r = eval_pos_high_r + eval_neg_high_r;

    tempvar num_q_high = a0_x - q_high_x;
    tempvar den_tmp_q_high = m_a0 * q_high_x + b_a0;
    tempvar den_neg_q_high = (0 - q_high_y) - den_tmp_q_high;
    tempvar eval_q_high = num_q_high / den_neg_q_high;

    tempvar rhs_high = eval_high_g + eval_high_r + eval_q_high;

    // base_rhs_high_shifted
    // decomposition of 2^128 in base -3
    tempvar ep_high_shifted = 5279154705627724249993186093248666011;
    tempvar en_high_shifted = 345561521626566187713367793525016877467;
    tempvar den_pos_q_high = q_high_y - den_tmp_q_high;
    tempvar eval_pos_q_high_shifted = (0 - ep_high_shifted) * num_q_high / den_pos_q_high;
    tempvar eval_neg_q_high_shifted = (0 - en_high_shifted) * num_q_high / den_neg_q_high;

    tempvar num_q_high_shifted = a0_x - q_high_shifted_x;
    tempvar den_tmp_q_high_shifted = m_a0 * q_high_shifted_x + b_a0;
    tempvar den_neg_q_high_shifted = (0 - q_high_shifted_y) - den_tmp_q_high_shifted;
    tempvar eval_q_high_shifted = num_q_high_shifted / den_neg_q_high_shifted;

    tempvar rhs_high_shifted = eval_pos_q_high_shifted + eval_neg_q_high_shifted +
        eval_q_high_shifted;

    tempvar c1 = base_rlc * base_rlc;
    tempvar c2 = c1 * base_rlc;

    tempvar rhs = base_rlc * rhs_low + c1 * rhs_high + c2 * rhs_high_shifted;

    assert lhs = rhs;

    return ();

    end:
}

// @dev Verify that Q = k*P
// It verifies that the equation (3) from the paper
// "Zero Knowledge Proofs of Elliptic Curve Inner Products
// from Principal Divisors and Weil Reciprocity", by Liam Eagen
// (source: https://eprint.iacr.org/2022/596.pdf, p.9) holds.
func ecip_1p(
    div_a_coeff_0: felt,
    div_a_coeff_1: felt,
    div_a_coeff_2: felt,
    div_a_coeff_3: felt,
    div_b_coeff_0: felt,
    div_b_coeff_1: felt,
    div_b_coeff_2: felt,
    div_b_coeff_3: felt,
    div_b_coeff_4: felt,
    div_c_coeff_0: felt,
    div_c_coeff_1: felt,
    div_c_coeff_2: felt,
    div_c_coeff_3: felt,
    div_c_coeff_4: felt,
    div_d_coeff_0: felt,
    div_d_coeff_1: felt,
    div_d_coeff_2: felt,
    div_d_coeff_3: felt,
    div_d_coeff_4: felt,
    div_d_coeff_5: felt,
    div_d_coeff_6: felt,
    div_d_coeff_7: felt,
    g_x: felt,
    g_y: felt,
    ep1_low: felt,
    en1_low: felt,
    sp1_low: felt,
    sn1_low: felt,
    ep1_high: felt,
    en1_high: felt,
    sp1_high: felt,
    sn1_high: felt,
    q_low_x: felt,
    q_low_y: felt,
    q_high_x: felt,
    q_high_y: felt,
    q_high_shifted_x: felt,
    q_high_shifted_y: felt,
    a0_x: felt,
    a0_y: felt,
    a: felt,
    b: felt,
    base_rlc: felt,
) {
    // Assert (g_x, g_y) is on curve
    assert g_y * g_y = g_x * g_x * g_x + a * g_x + b;
    // Assert (a0_x, a0_y) is on curve
    assert a0_y * a0_y = a0_x * a0_x * a0_x + a * a0_x + b;
    // Assert (q_low_x, q_low_y) is on curve
    assert q_low_y * q_low_y = q_low_x * q_low_x * q_low_x + a * q_low_x + b;
    // Assert (q_high_x, q_high_y) is on curve
    assert q_high_y * q_high_y = q_high_x * q_high_x * q_high_x + a * q_high_x + b;
    // Assert (q_high_shifted_x, q_high_shifted_y) is on curve
    assert q_high_shifted_y * q_high_shifted_y = q_high_shifted_x * q_high_shifted_x *
        q_high_shifted_x + a * q_high_shifted_x + b;

    // slope a0, a0
    tempvar m_a0 = (3 * a0_x * a0_x + a) / (2 * a0_y);
    // intercept a0
    tempvar b_a0 = a0_y - a0_x * m_a0;
    tempvar x_a2 = m_a0 * m_a0 - 2 * a0_x;
    tempvar y_a2 = 0 - (m_a0 * (a0_x - x_a2) - a0_y);
    // Slope a0, a2
    tempvar m_a0a2 = (y_a2 - a0_y) / (x_a2 - a0_x);
    tempvar coeff2 = (2 * y_a2 * (a0_x - x_a2)) / (3 * x_a2 * x_a2 + a - 2 * m_a0a2 * y_a2);
    tempvar coeff0 = coeff2 + 2 * m_a0a2;

    // LHS = coeff0 * f(a0) - coeff2 * f(a2), with f(x, y) = a(x) + y*b(x)
    // f(a0)
    tempvar eval_log_div_a_num_a0_x = div_a_coeff_0 + a0_x * (
        div_a_coeff_1 + a0_x * (div_a_coeff_2 + a0_x * div_a_coeff_3)
    );
    tempvar eval_log_div_a_den_a0_x = div_b_coeff_0 + a0_x * (
        div_b_coeff_1 + a0_x * (div_b_coeff_2 + a0_x * (div_b_coeff_3 + a0_x * div_b_coeff_4))
    );
    tempvar eval_log_div_b_num_a0_x = div_c_coeff_0 + a0_x * (
        div_c_coeff_1 + a0_x * (div_c_coeff_2 + a0_x * (div_c_coeff_3 + a0_x * div_c_coeff_4))
    );
    tempvar eval_log_div_b_den_a0_x = div_d_coeff_0 + a0_x * (
        div_d_coeff_1 +
        a0_x * (
            div_d_coeff_2 +
            a0_x * (
                div_d_coeff_3 +
                a0_x * (
                    div_d_coeff_4 +
                    a0_x * (div_d_coeff_5 + a0_x * (div_d_coeff_6 + a0_x * div_d_coeff_7))
                )
            )
        )
    );

    tempvar f_a0 = eval_log_div_a_num_a0_x / eval_log_div_a_den_a0_x + a0_y *
        eval_log_div_b_num_a0_x / eval_log_div_b_den_a0_x;

    // f(a2)
    tempvar eval_log_div_a_num_x_a2 = div_a_coeff_0 + x_a2 * (
        div_a_coeff_1 + x_a2 * (div_a_coeff_2 + x_a2 * div_a_coeff_3)
    );
    tempvar eval_log_div_a_den_x_a2 = div_b_coeff_0 + x_a2 * (
        div_b_coeff_1 + x_a2 * (div_b_coeff_2 + x_a2 * (div_b_coeff_3 + x_a2 * div_b_coeff_4))
    );
    tempvar eval_log_div_b_num_x_a2 = div_c_coeff_0 + x_a2 * (
        div_c_coeff_1 + x_a2 * (div_c_coeff_2 + x_a2 * (div_c_coeff_3 + x_a2 * div_c_coeff_4))
    );
    tempvar eval_log_div_b_den_x_a2 = div_d_coeff_0 + x_a2 * (
        div_d_coeff_1 +
        x_a2 * (
            div_d_coeff_2 +
            x_a2 * (
                div_d_coeff_3 +
                x_a2 * (
                    div_d_coeff_4 +
                    x_a2 * (div_d_coeff_5 + x_a2 * (div_d_coeff_6 + x_a2 * div_d_coeff_7))
                )
            )
        )
    );
    tempvar f_a2 = eval_log_div_a_num_x_a2 / eval_log_div_a_den_x_a2 + y_a2 *
        eval_log_div_b_num_x_a2 / eval_log_div_b_den_x_a2;

    // Compute LHS
    tempvar lhs = coeff0 * f_a0 - coeff2 * f_a2;

    // base_rhs_low
    tempvar num_g = a0_x - g_x;
    tempvar den_tmp_g = m_a0 * g_x + b_a0;
    tempvar den_pos_g = g_y - den_tmp_g;
    tempvar den_neg_g = (0 - g_y) - den_tmp_g;
    tempvar eval_pos_low_g = sp1_low * ep1_low * num_g / den_pos_g;
    tempvar eval_neg_low_g = sn1_low * en1_low * num_g / den_neg_g;
    tempvar eval_low_g = eval_pos_low_g + eval_neg_low_g;

    tempvar num_q_low = a0_x - q_low_x;
    tempvar den_tmp_q_low = m_a0 * q_low_x + b_a0;
    tempvar den_neg_q_low = (0 - q_low_y) - den_tmp_q_low;
    tempvar eval_q_low = num_q_low / den_neg_q_low;

    tempvar rhs_low = eval_low_g + eval_q_low;

    // base_rhs_high
    tempvar eval_pos_high_g = sp1_high * ep1_high * num_g / den_pos_g;
    tempvar eval_neg_high_g = sn1_high * en1_high * num_g / den_neg_g;
    tempvar eval_high_g = eval_pos_high_g + eval_neg_high_g;

    tempvar num_q_high = a0_x - q_high_x;
    tempvar den_tmp_q_high = m_a0 * q_high_x + b_a0;
    tempvar den_neg_q_high = (0 - q_high_y) - den_tmp_q_high;
    tempvar eval_q_high = num_q_high / den_neg_q_high;

    tempvar rhs_high = eval_high_g + eval_q_high;

    // base_rhs_high_shifted
    // decomposition of 2^128 in base -3
    tempvar ep_high_shifted = 5279154705627724249993186093248666011;
    tempvar en_high_shifted = 345561521626566187713367793525016877467;
    tempvar den_pos_q_high = q_high_y - den_tmp_q_high;
    tempvar eval_pos_q_high_shifted = (0 - ep_high_shifted) * num_q_high / den_pos_q_high;
    tempvar eval_neg_q_high_shifted = (0 - en_high_shifted) * num_q_high / den_neg_q_high;

    tempvar num_q_high_shifted = a0_x - q_high_shifted_x;
    tempvar den_tmp_q_high_shifted = m_a0 * q_high_shifted_x + b_a0;
    tempvar den_neg_q_high_shifted = (0 - q_high_shifted_y) - den_tmp_q_high_shifted;
    tempvar eval_q_high_shifted = num_q_high_shifted / den_neg_q_high_shifted;

    tempvar rhs_high_shifted = eval_pos_q_high_shifted + eval_neg_q_high_shifted +
        eval_q_high_shifted;

    tempvar c1 = base_rlc * base_rlc;
    tempvar c2 = c1 * base_rlc;

    tempvar rhs = base_rlc * rhs_low + c1 * rhs_high + c2 * rhs_high_shifted;

    assert lhs = rhs;

    return ();

    end:
}
