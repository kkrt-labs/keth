%builtins syscall

from starkware.starknet.common.syscalls import get_block_number

func main{syscall_ptr : felt*}() {
    let (block_number) = get_block_number();
    %{ print(ids.block_number) %}
    return ();
}
