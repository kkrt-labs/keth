%builtins output range_check

from src.model import model

func main{output_ptr: felt*, range_check_ptr}() {

    let address = 0xdead;
    let res = model.Option(is_some=1, value=address);

    return ();
}
