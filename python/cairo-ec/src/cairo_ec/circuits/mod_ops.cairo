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

// @dev Assert that a point is a quadratic residue by checking that either root is actually the square root of x
//      (res = True => root^2 = x) or root is the square root of g * x (res = False => root^2 = g * x),
//      which mean that x is not a quadratic residue because g * x is.
func assert_is_quad_residue(x: felt, root: felt, g: felt, is_quad_residue: felt) {
    assert is_quad_residue * (1 - is_quad_residue) = 0;
    assert root * root = x * is_quad_residue + g * x * (1 - is_quad_residue);

    return ();

    end:
}
