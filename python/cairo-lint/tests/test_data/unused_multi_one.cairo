from starkware.cairo.common.registers import get_fp_and_pc, get_label_location
from starkware.cairo.common.math import assert_le, assert_lt, assert_nn

func main() {
    let (__fp__, __pc__) = get_fp_and_pc();
    assert_lt(5, 10);
    assert_nn(1);
}
