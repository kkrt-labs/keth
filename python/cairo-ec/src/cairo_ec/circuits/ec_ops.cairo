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

// @dev Verify that Q = k1*P1 + k2*P2
// It verifies that the equation (3) from the paper
// "Zero Knowledge Proofs of Elliptic Curve Inner Products
// from Principal Divisors and Weil Reciprocity", by Liam Eagen
// (source: https://eprint.iacr.org/2022/596.pdf, p.9) holds.
func ecip_2P(
    cst_0: felt,
    cst_1: felt,
    cst_2: felt,
    cst_3: felt,
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
    base_rlc: felt,
) {
    // Assert (x_g, y_g) is on curve
    assert y_g * y_g = x_g * x_g * x_g + a;
    // Assert (x_r, y_r) is on curve
    assert y_r * y_r = x_r * x_r * x_r + a;
    // Assert (x_a0, y_a0) is on curve
    assert y_a0 * y_a0 = x_a0 * x_a0 * x_a0 + a;

    // _slope_intercept_same_point(a0, a)
    // Goal: compute slope intercept of a0 (used in RHS) and coeff0 & coeff2 for LGS
    // Compute slope: m_a0 = (3 * x_a0^2 + a) /2 * y_a0
    let m_a0 = (3 * x_a0 * x_a0 + a) / (2 * y_a0);
    // Compute intercept: b_a0 = y_a0 - x_a0 * m
    let b_a0 = y_a0 - x_a0 * m_a0;
    // Compute a2: a2 = -2*A0
    let x_a2 = m_a0 * m_a0 - 2 * x_a0;
    let y_a2 = -(m_a0 * (x_a0 - x_a2) - y_a0);
    // Compute slope a0 a2: ma0a2 = (y_a2 - y_a0) / (x_a2 - x_a0)
    let m_a0a2 = (y_a2 - y_a0) / (x_a2 - x_a0);
    // Compute coeff2: coeff2 = (2 * y_a2) * (x_a0 - x_a2) / (3 * x_a2^2 = a - 2 * m * y_a2)
    let coeff2 = (2 * y_a2) * (x_a0 - x_a2) / (3 * x_a2 * x_a2 + a - 2 * m_a0a2 * y_a2);
    // Compute coeff0: coeff0 = coeff2 + 2 * m_a0a2
    let coeff0 = coeff2 + 2 * m_a0a2;

    // Compute LHS = coeff0 * F(a0) - coeff2 * F(a2), with F(x, y) = a(x) + y*b(x)
    // Compute F_a0
    // eval log_div_a_num in x_a0
    let eval_log_div_a_num_x_a0 = div_a_coeff_0 + x_a0 * (
        div_a_coeff_1 + x_a0 * (div_a_coeff_2 + x_a0 * (div_a_coeff_3 + x_a0 * (div_a_coeff_4)))
    );
    // eval log_div_a_den in x_a0
    let eval_log_div_a_den_x_a0 = div_b_coeff_0 + x_a0 * (
        div_b_coeff_1 +
        x_a0 * (
            div_b_coeff_2 + x_a0 * (div_b_coeff_3 + x_a0 * (div_b_coeff_4 + x_a0 * (div_b_coeff_5)))
        )
    );
    // eval log_div_b_num in x_a0
    let eval_log_div_b_num_x_a0 = div_c_coeff_0 + x_a0 * (
        div_c_coeff_1 +
        x_a0 * (
            div_c_coeff_2 + x_a0 * (div_c_coeff_3 + x_a0 * (div_c_coeff_4 + x_a0 * (div_c_coeff_5)))
        )
    );
    // eval log_div_b_den in x_a0
    let eval_log_div_b_den_x_a0 = div_d_coeff_0 + x_a0 * (
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

    let f_a0 = eval_log_div_a_num_x_a0 / eval_log_div_a_den_x_a0 + y_a0 * eval_log_div_b_num_x_a0 /
        eval_log_div_b_den_x_a0;

    // Compute F_a2
    // eval log_div_a_num in x_a2
    let eval_log_div_a_num_x_a2 = div_a_coeff_0 + x_a2 * (
        div_a_coeff_1 + x_a2 * (div_a_coeff_2 + x_a2 * (div_a_coeff_3 + x_a2 * (div_a_coeff_4)))
    );
    // eval log_div_a_den in x_a2
    let eval_log_div_a_den_x_a2 = div_b_coeff_0 + x_a2 * (
        div_b_coeff_1 +
        x_a2 * (
            div_b_coeff_2 + x_a2 * (div_b_coeff_3 + x_a2 * (div_b_coeff_4 + x_a2 * (div_b_coeff_5)))
        )
    );
    // eval log_div_b_num in x_a2
    let eval_log_div_b_num_x_a2 = div_c_coeff_0 + x_a2 * (
        div_c_coeff_1 +
        x_a2 * (
            div_c_coeff_2 + x_a2 * (div_c_coeff_3 + x_a2 * (div_c_coeff_4 + x_a2 * (div_c_coeff_5)))
        )
    );
    // eval log_div_b_den in x_a2
    let eval_log_div_b_den_x_a2 = div_d_coeff_0 + x_a2 * (
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

    let f_a2 = eval_log_div_a_num_x_a2 / eval_log_div_a_den_x_a2 + y_a0 * eval_log_div_b_num_x_a2 /
        eval_log_div_b_den_x_a2;

    // Compute LHS
    let lhs = coeff0 * f_a0 + coeff2 * f_a2;

    // Compute RHS: rhs = c0 * base_rhs_low + c1*base_rhs_high + c2*base_rhs_high_shifted
    // compute base_rhs_low
    let base_rhs_low = (x_a0 - x_g) * (
        sp1_low * ep1_low / (y_a0 - (m_a0 * x_g + b_a0)) -
        sn1_low * en1_low / (y_a0 + (m_a0 * x_g + b_a0))
    ) + (x_a0 - x_r) * (
        sp2_low * ep2_low / (y_a0 - (m_a0 * x_r + b_a0)) -
        sn2_low * en2_low / (y_a0 + (m_a0 * x_r + b_a0))
    ) - (x_a0 - x_q_low) / (y_q_low + (m_a0 * x_q_low + b_a0));
    // compute base_rhs_high
    let base_rhs_high = (x_a0 - x_g) * (
        sp1_high * ep1_high / (y_a0 - (m_a0 * x_g + b_a0)) -
        sn1_high * en1_high / (y_a0 + (m_a0 * x_g + b_a0))
    ) + (x_a0 - x_r) * (
        sp2_high * ep2_high / (y_a0 - (m_a0 * x_r + b_a0)) -
        sn2_high * en2_high / (y_a0 + (m_a0 * x_r + b_a0))
    ) - (x_a0 - x_q_high) / (y_q_high + (m_a0 * x_q_high + b_a0));
    // compute base_rhs_high_shifted
    let ep_high_shifted = 5279154705627724249993186093248666011;
    let en_high_shifted = 345561521626566187713367793525016877467;
    let sp_high_shifted = -1;
    let sn_high_shifted = -1;
    let base_rhs_high_shifted = (x_a0 - x_q_high_shifted) * (
        sp_high_shifted * ep_high_shifted / (y_a0 - (m_a0 * x_q_high_shifted + b_a0)) -
        sn_high_shifted * en_high_shifted / (y_a0 + (m_a0 * x_q_high_shifted + b_a0))
    ) - (x_a0 - x_q_high_shifted) / (y_q_high_shifted + (m_a0 * x_q_high_shifted + b_a0));
    // Compute c0: base_rlc
    // Compute c1: base_rlc^2
    let c1 = base_rlc * base_rlc;
    // Compute c2: base_rlc^3
    let c2 = c1 * base_rlc;

    let rhs = base_rlc * base_rhs_low + c1 * base_rhs_high + c2 * base_rhs_high_shifted;

    // Assert that RHS - LHZ == 0

    assert lhs = rhs;

    return ();

    end:
}
