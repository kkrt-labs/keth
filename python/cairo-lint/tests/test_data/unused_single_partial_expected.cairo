from starkware.cairo.common.math import assert_lt

func main() {
    tempvar x = 5;
    assert_lt(x, 10);
}
