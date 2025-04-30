// cairo-lint: disable
from starkware.cairo.common.registers import get_fp_and_pc, get_label_location
from starkware.cairo.common.alloc import alloc

func main() {
    let (__fp__, __pc__) = get_fp_and_pc();
}
