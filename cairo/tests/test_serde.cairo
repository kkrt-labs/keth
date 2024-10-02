from starkware.cairo.common.dict import dict_read
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import HashBuiltin

from src.model import model
from src.account import Internals, Account
from src.state import State

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

func test_state{pedersen_ptr: HashBuiltin*}() -> model.State* {
    alloc_locals;
    tempvar state: model.State*;
    %{ state %}

    with state {
        let account = State.get_account(0xc0de);
        tempvar key = new Uint256(0, 0);
        let (account, value) = Account.read_storage(account, key);
        tempvar key = new Uint256(1, 0);
        let (account, value) = Account.read_storage(account, key);
        tempvar key = new Uint256(2, 0);
        let (account, value) = Account.read_storage(account, key);
        State.update_account(0xc0de, account);

        let account = State.get_account(0x000f3df6d732807ef1319fb7b8bb8522d0beac02);
        tempvar key = new Uint256(0xf2, 0);
        let (account, value) = Account.read_storage(account, key);
        State.update_account(0x000f3df6d732807ef1319fb7b8bb8522d0beac02, account);

        let account = State.get_account(0xa94f5374fce5edbc8e2a8697c15331677e6ebf0b);
        tempvar key = new Uint256(0, 0);
        let (account, value) = Account.read_storage(account, key);
        State.update_account(0xa94f5374fce5edbc8e2a8697c15331677e6ebf0b, account);
    }
    return state;
}
