func add(x: felt, y: felt) -> felt {
    return x + y;

    end:
}

func sub(x: felt, y: felt) -> felt {
    return x - y;

    end:
}

func mul(x: felt, y: felt) -> felt {
    return x * y;

    end:
}

func div(x: felt, y: felt) -> felt {
    return x / y;

    end:
}

func diff_ratio(x: felt, y: felt) -> felt {
    return (x - y) / (x - y);

    end:
}

func sum_ratio(x: felt, y: felt) -> felt {
    return (x + y) / (x + y);

    end:
}

func inv(x: felt) -> felt {
    return 1 / x;

    end:
}

// @dev Assert that a point is, or is not, a quadratic residue by checking that either root is actually the square root of x
//      (is_quad_residue = True => root^2 = x) or root is the square root of g * x (is_quad_residue = False => root^2 = g * x),
//      which mean that x is not a quadratic residue because g * x is.
// @param x The value to check if it's a quadratic residue
// @param root The root of x or g * x
// @param g The generator point
// @param is_quad_residue True if x is a quadratic residue, False otherwise
func assert_is_quad_residue(x: felt, root: felt, g: felt, is_quad_residue: felt) {
    assert is_quad_residue * (1 - is_quad_residue) = 0;
    assert root * root = x * is_quad_residue + g * x * (1 - is_quad_residue);

    return ();

    end:
}

// @dev Assert that two values are equal
// @param x The first value
// @param y The second value
func assert_eq(x: felt, y: felt) {
    assert x = y;

    return ();

    end:
}

// @dev Assert that two values are not equal
// @param x The first value
// @param y The second value
func assert_neq(x: felt, y: felt) {
    tempvar inv_diff = 1 / (x - y);  // Will fail if x == y

    return ();

    end:
}

// @dev Compute the negation of a value
// @param y The value to negate
// @return The negation of y
func neg(y: felt) -> felt {
    return 0 - y;

    end:
}

// @dev Assert that one value is the negation of another
// @param x The first value
// @param y The second value
func assert_neg(x: felt, y: felt) {
    assert x + y = 0;

    return ();

    end:
}

// @dev Assert that one value is not the negation of another
// @param x The first value
// @param y The second value
func assert_not_neg(x: felt, y: felt) {
    tempvar inv_sum = 1 / (x + y);  // Will fail if x + y == 0

    return ();

    end:
}
