from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin
from ethereum_types.numeric import U256, U256Struct
from ethereum.cancun.fork_types import (
    AddressAccountDictAccess,
    TupleAddressBytes32U256DictAccess,
    MappingAddressAccount,
    MappingAddressAccountStruct,
    SetAddress,
    SetAddressStruct,
    OptionalAccount,
    AccountStruct,
    MappingTupleAddressBytes32U256,
    MappingTupleAddressBytes32U256Struct,
)
from ethereum.cancun.state import State, StateStruct
from ethereum.cancun.trie import (
    TrieAddressOptionalAccount,
    TrieAddressOptionalAccountStruct,
    TrieTupleAddressBytes32U256,
    TrieTupleAddressBytes32U256Struct,
)
from mpt.types import AccountDiff, StorageDiffEntry, StorageDiff
from cairo_core.numeric import bool
from mpt.hash_diff import hash_state_account_diff, hash_state_storage_diff

// @notice Entrypoint for testing hashing account diffs directly from a formatted State object.
func test_hash_state_diff{range_check_ptr, poseidon_ptr: PoseidonBuiltin*}(
    account_diff: AccountDiff
) -> felt {
    alloc_locals;
    // Format the `account_diff` in the `AddressAccountDictAccess*` format, part of the state struct.
    let (local dict_ptr_start: AddressAccountDictAccess*) = alloc();
    let dict_ptr_end = dict_ptr_start;
    helper_format_account_diff{dict_ptr_end=dict_ptr_end}(account_diff, 0);

    tempvar _main_trie = TrieAddressOptionalAccount(
        new TrieAddressOptionalAccountStruct(
            secured=bool(1),
            default=OptionalAccount(cast(0, AccountStruct*)),
            _data=MappingAddressAccount(
                new MappingAddressAccountStruct(
                    dict_ptr_start, dict_ptr_end, cast(0, MappingAddressAccountStruct*)
                ),
            ),
        ),
    );

    // unused
    tempvar _storage_tries = TrieTupleAddressBytes32U256(
        cast(0, TrieTupleAddressBytes32U256Struct*)
    );
    tempvar created_accounts = SetAddress(cast(0, SetAddressStruct*));
    tempvar original_storage_tries = TrieTupleAddressBytes32U256(
        cast(0, TrieTupleAddressBytes32U256Struct*)
    );

    tempvar state = State(
        new StateStruct(_main_trie, _storage_tries, created_accounts, original_storage_tries)
    );

    let hashed_state_account_diff = hash_state_account_diff(state);

    return hashed_state_account_diff;
}

// @notice Helper function to format the `account_diff` to a series of `AddressAccountDictAccess` in a single segment,
// part of the state struct main trie.
func helper_format_account_diff{dict_ptr_end: AddressAccountDictAccess*}(
    account_diff: AccountDiff, index: felt
) {
    if (index == account_diff.value.len) {
        return ();
    }
    tempvar entry_ptr = cast(account_diff.value.data[index].value, AddressAccountDictAccess*);
    assert [dict_ptr_end] = [entry_ptr];

    let dict_ptr_end_new = dict_ptr_end + AddressAccountDictAccess.SIZE;
    return helper_format_account_diff{dict_ptr_end=dict_ptr_end_new}(account_diff, index + 1);
}

// @notice Entrypoint for testing hashing storage diffs directly from a formatted State object.
func test_hash_storage_diff{range_check_ptr, poseidon_ptr: PoseidonBuiltin*}(
    storage_diff: StorageDiff
) -> felt {
    alloc_locals;
    // Format the `storage_diff` in the `StorageDiffEntry*` format, part of the state struct.
    let (local dict_ptr_start: TupleAddressBytes32U256DictAccess*) = alloc();
    let dict_ptr_end = dict_ptr_start;
    helper_format_storage_diff{dict_ptr_end=dict_ptr_end}(storage_diff, 0);

    tempvar _storage_tries = TrieTupleAddressBytes32U256(
        new TrieTupleAddressBytes32U256Struct(
            secured=bool(1),
            default=U256(cast(0, U256Struct*)),
            _data=MappingTupleAddressBytes32U256(
                new MappingTupleAddressBytes32U256Struct(
                    dict_ptr_start, dict_ptr_end, cast(0, MappingTupleAddressBytes32U256Struct*)
                ),
            ),
        ),
    );

    // unused
    tempvar _main_trie = TrieAddressOptionalAccount(cast(0, TrieAddressOptionalAccountStruct*));
    tempvar created_accounts = SetAddress(cast(0, SetAddressStruct*));
    tempvar original_storage_tries = TrieTupleAddressBytes32U256(
        cast(0, TrieTupleAddressBytes32U256Struct*)
    );

    tempvar state = State(
        new StateStruct(_main_trie, _storage_tries, created_accounts, original_storage_tries)
    );

    let hashed_storage_diff = hash_state_storage_diff(state);

    return hashed_storage_diff;
}

func helper_format_storage_diff{dict_ptr_end: TupleAddressBytes32U256DictAccess*}(
    storage_diff: StorageDiff, index: felt
) {
    if (index == storage_diff.value.len) {
        return ();
    }

    let entry_ptr = cast(storage_diff.value.data[index].value, TupleAddressBytes32U256DictAccess*);
    assert [dict_ptr_end] = [entry_ptr];

    let dict_ptr_end_new = dict_ptr_end + TupleAddressBytes32U256DictAccess.SIZE;
    return helper_format_storage_diff{dict_ptr_end=dict_ptr_end_new}(storage_diff, index + 1);
}
