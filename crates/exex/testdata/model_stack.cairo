%builtins output range_check

from src.model import model
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.common.uint256 import Uint256

func main{output_ptr: felt*, range_check_ptr}() {
    let (dict_ptr_start: DictAccess*) = default_dict_new(0);
    let stack = model.Stack(dict_ptr_start, dict_ptr_start, 0);
    let num = Uint256(34623634663146736, 598249824422424658356);

    return ();
}
