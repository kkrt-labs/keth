from starkware.cairo.common.math import assert_le

// cairo-lint: disable
from starkware.cairo.common.alloc import alloc

func main() {
    tempvar x = 5;
    assert_le(x, 10);
}
