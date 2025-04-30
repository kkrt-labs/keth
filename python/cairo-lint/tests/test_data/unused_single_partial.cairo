from starkware.cairo.common.math import assert_le, assert_lt, assert_nn

func main() {
    tempvar x = 5;
    assert_lt(x, 10);
}
