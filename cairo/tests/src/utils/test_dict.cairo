%builtins range_check

from starkware.cairo.common.cairo_builtins import HashBuiltin
from starkware.cairo.common.default_dict import default_dict_new, default_dict_finalize
from starkware.cairo.common.dict import dict_write, dict_read
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.uint256 import Uint256

from src.utils.dict import dict_copy

func test__dict_copy__should_return_copied_dict{range_check_ptr}() {
    alloc_locals;
    let default_value = 0xdead;
    let (dict_ptr_start) = default_dict_new(default_value);
    let dict_ptr = dict_ptr_start;
    let key = 0x7e1;
    with dict_ptr {
        let (value) = dict_read(key);
        assert value = default_value;
        dict_write(key, 0xff);
        let (value) = dict_read(key);
        assert value = 0xff;
        dict_write(key + 1, 0xff + 1);
        dict_write(key + 2, 0xff + 2);
        dict_write(key + 3, 0xff + 3);
        dict_write(key + 4, 0xff + 4);
    }
    local dict_size = dict_ptr - dict_ptr_start;
    let (new_start, new_ptr) = dict_copy(dict_ptr_start, dict_ptr);

    assert new_ptr - new_start = dict_size;

    let dict_ptr = new_ptr;
    with dict_ptr {
        let (value) = dict_read(key);
        assert value = 0xff;
        let (value) = dict_read(key + 1);
        assert value = 0xff + 1;
        let (value) = dict_read(key + 2);
        assert value = 0xff + 2;
        let (value) = dict_read(key + 3);
        assert value = 0xff + 3;
        let (value) = dict_read(key + 4);
        assert value = 0xff + 4;
        let (value) = dict_read(key + 10);
        assert value = default_value;
    }

    return ();
}
