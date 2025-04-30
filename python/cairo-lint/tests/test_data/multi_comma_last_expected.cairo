from starkware.cairo.common.math import assert_le, assert_lt

func main() {
    assert_le(1, 2);
    assert_lt(1, 2);
}
