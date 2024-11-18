from ethereum.base_types import Uint
from ethereum.utils.numeric import ceil32, divmod

const GAS_INIT_CODE_WORD_COST = 2;

func init_code_cost{range_check_ptr}(init_code_length: Uint) -> Uint {
    let length = ceil32(init_code_length);
    let (words, _) = divmod(length.value, 32);
    let cost = Uint(GAS_INIT_CODE_WORD_COST * words);
    return cost;
}
