%builtins output range_check

from src.model import model
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict import DictAccess

func main{output_ptr: felt*, range_check_ptr}() {
    let (word_dict_start: DictAccess*) = default_dict_new(0);
    let stack = model.Memory(word_dict_start, word_dict_start, 0);

    return ();
}
