from starkware.cairo.common.dict import dict_read
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import HashBuiltin

from programs.os import main
from src.model import model
from src.account import Internals

func test_os{pedersen_ptr: HashBuiltin*, output_ptr: felt*}() {
    main();

    return ();
}

func test_block() -> model.Block* {
    tempvar block: model.Block*;
    %{ block %}
    return block;
}

func test_account{pedersen_ptr: HashBuiltin*}() -> model.Account* {
    tempvar account: model.Account*;
    %{ account %}

    let dict_ptr = account.valid_jumpdests;
    with dict_ptr {
        dict_read(120);
        dict_read(138);
    }
    let dict_ptr = account.storage;
    with dict_ptr {
        tempvar key = new Uint256(1, 0);
        let (address) = Internals._storage_addr(key);
        dict_read(address);
    }

    return account;
}
