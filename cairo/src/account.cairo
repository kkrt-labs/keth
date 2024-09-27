from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.cairo_builtins import HashBuiltin, KeccakBuiltin, BitwiseBuiltin
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict import dict_read, dict_write
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.math_cmp import is_not_zero
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.hash_state import (
    hash_finalize,
    hash_init,
    hash_update,
    hash_update_single,
    hash_update_with_hashchain,
)
from starkware.cairo.lang.compiler.lib.registers import get_ap
from starkware.cairo.common.find_element import find_element

from src.interfaces.interfaces import ICairo1Helpers
from src.model import model
from src.utils.dict import default_dict_copy
from src.utils.utils import Helpers
from src.utils.bytes import keccak

namespace Account {
    // @notice Create a new account
    // @dev New contract accounts start at nonce=1.
    // @param address The address of the account
    // @param code_len The length of the code
    // @param code The pointer to the code
    // @param nonce The initial nonce
    // @return The updated state
    // @return The account
    func init(
        code_len: felt, code: felt*, code_hash: Uint256*, nonce: felt, balance: Uint256*
    ) -> model.Account* {
        let (storage_start) = default_dict_new(0);
        let (transient_storage_start) = default_dict_new(0);
        let (valid_jumpdests_start) = default_dict_new(0);
        return new model.Account(
            code_len=code_len,
            code=code,
            code_hash=code_hash,
            storage_start=storage_start,
            storage=storage_start,
            transient_storage_start=transient_storage_start,
            transient_storage=transient_storage_start,
            valid_jumpdests_start=valid_jumpdests_start,
            valid_jumpdests=valid_jumpdests_start,
            nonce=nonce,
            balance=balance,
            selfdestruct=0,
            created=0,
        );
    }

    // @dev Copy the Account to safely mutate the storage
    // @dev Squash dicts used internally
    // @param self The pointer to the Account
    func copy{range_check_ptr}(self: model.Account*) -> model.Account* {
        alloc_locals;
        let (storage_start, storage) = default_dict_copy(self.storage_start, self.storage);
        let (transient_storage_start, transient_storage) = default_dict_copy(
            self.transient_storage_start, self.transient_storage
        );
        let (valid_jumpdests_start, valid_jumpdests) = default_dict_copy(
            self.valid_jumpdests_start, self.valid_jumpdests
        );
        return new model.Account(
            code_len=self.code_len,
            code=self.code,
            code_hash=self.code_hash,
            storage_start=storage_start,
            storage=storage,
            transient_storage_start=transient_storage_start,
            transient_storage=transient_storage,
            valid_jumpdests_start=valid_jumpdests_start,
            valid_jumpdests=valid_jumpdests,
            nonce=self.nonce,
            balance=self.balance,
            selfdestruct=self.selfdestruct,
            created=self.created,
        );
    }

    // @notice Read a given storage
    // @dev Try to retrieve in the local Dict<Uint256*> first, and returns 0 otherwise.
    // @param self The pointer to the execution Account.
    // @param key The pointer to the storage key
    // @return The updated Account
    // @return The read value
    func read_storage{pedersen_ptr: HashBuiltin*}(self: model.Account*, key: Uint256*) -> (
        model.Account*, Uint256*
    ) {
        alloc_locals;
        let storage = self.storage;
        let (local storage_addr) = Internals._storage_addr(key);
        let (pointer) = dict_read{dict_ptr=storage}(key=storage_addr);
        local value_ptr: Uint256*;
        if (pointer != 0) {
            assert value_ptr = cast(pointer, Uint256*);
        } else {
            assert value_ptr = new Uint256(0, 0);
        }

        tempvar self = new model.Account(
            code_len=self.code_len,
            code=self.code,
            code_hash=self.code_hash,
            storage_start=self.storage_start,
            storage=storage,
            transient_storage_start=self.transient_storage_start,
            transient_storage=self.transient_storage,
            valid_jumpdests_start=self.valid_jumpdests_start,
            valid_jumpdests=self.valid_jumpdests,
            nonce=self.nonce,
            balance=self.balance,
            selfdestruct=self.selfdestruct,
            created=self.created,
        );
        return (self, value_ptr);
    }

    // @notive Read the first value of a given storage slot
    // @dev The storage needs to exists already, to this should be used only
    //      after a storage_read or storage_write has been done
    func fetch_original_storage{pedersen_ptr: HashBuiltin*}(
        self: model.Account*, key: Uint256*
    ) -> Uint256 {
        alloc_locals;
        let storage = self.storage;
        let (local storage_addr) = Internals._storage_addr(key);

        let (pointer) = dict_read{dict_ptr=storage}(key=storage_addr);
        local value_ptr: Uint256*;
        if (pointer != 0) {
            assert value_ptr = cast(pointer, Uint256*);
        } else {
            assert value_ptr = new Uint256(0, 0);
        }
    }

    // @notice Update a storage key with the given value
    // @param self The pointer to the Account.
    // @param key The pointer to the Uint256 storage key
    // @param value The pointer to the Uint256 value
    func write_storage{pedersen_ptr: HashBuiltin*, range_check_ptr}(
        self: model.Account*, key: Uint256*, value: Uint256*
    ) -> model.Account* {
        alloc_locals;
        local storage: DictAccess* = self.storage;
        let (storage_addr) = Internals._storage_addr(key);
        dict_write{dict_ptr=storage}(key=storage_addr, new_value=cast(value, felt));
        tempvar self = new model.Account(
            code_len=self.code_len,
            code=self.code,
            code_hash=self.code_hash,
            storage_start=self.storage_start,
            storage=storage,
            transient_storage_start=self.transient_storage_start,
            transient_storage=self.transient_storage,
            valid_jumpdests_start=self.valid_jumpdests_start,
            valid_jumpdests=self.valid_jumpdests,
            nonce=self.nonce,
            balance=self.balance,
            selfdestruct=self.selfdestruct,
            created=self.created,
        );
        return self;
    }

    // @notice Read a given key in the transient storage
    // @param self The pointer to the execution Account.
    // @param key The pointer to the storage key
    // @return The updated Account
    // @return The read value
    func read_transient_storage{pedersen_ptr: HashBuiltin*, range_check_ptr}(
        self: model.Account*, key: Uint256*
    ) -> (model.Account*, Uint256*) {
        alloc_locals;
        let transient_storage = self.transient_storage;
        let (local storage_addr) = Internals._storage_addr(key);
        let (pointer) = dict_read{dict_ptr=transient_storage}(key=storage_addr);
        local value_ptr: Uint256*;

        // Case reading from local storage
        if (pointer != 0) {
            assert value_ptr = cast(pointer, Uint256*);
        } else {
            assert value_ptr = new Uint256(0, 0);
        }
        tempvar self = new model.Account(
            code_len=self.code_len,
            code=self.code,
            code_hash=self.code_hash,
            storage_start=self.storage_start,
            storage=self.storage,
            transient_storage_start=self.transient_storage_start,
            transient_storage=transient_storage,
            valid_jumpdests_start=self.valid_jumpdests_start,
            valid_jumpdests=self.valid_jumpdests,
            nonce=self.nonce,
            balance=self.balance,
            selfdestruct=self.selfdestruct,
            created=self.created,
        );
        return (self, value_ptr);
    }

    // @notice Updates a transient storage key with the given value
    // @param self The pointer to the Account.
    // @param key The pointer to the Uint256 storage key
    // @param value The pointer to the Uint256 value
    func write_transient_storage{pedersen_ptr: HashBuiltin*, range_check_ptr}(
        self: model.Account*, key: Uint256*, value: Uint256*
    ) -> model.Account* {
        alloc_locals;
        local transient_storage: DictAccess* = self.transient_storage;
        let (storage_addr) = Internals._storage_addr(key);
        dict_write{dict_ptr=transient_storage}(key=storage_addr, new_value=cast(value, felt));
        tempvar self = new model.Account(
            code_len=self.code_len,
            code=self.code,
            code_hash=self.code_hash,
            storage_start=self.storage_start,
            storage=self.storage,
            transient_storage_start=self.transient_storage_start,
            transient_storage=transient_storage,
            valid_jumpdests_start=self.valid_jumpdests_start,
            valid_jumpdests=self.valid_jumpdests,
            nonce=self.nonce,
            balance=self.balance,
            selfdestruct=self.selfdestruct,
            created=self.created,
        );
        return self;
    }

    // @notice Set the account's bytecode, valid jumpdests and mark it as created during this
    // transaction.
    // @dev The only reason to set code after creation is in create/deploy operations where
    //      the account exists from the beginning for setting storages, but the
    //      deployed bytecode is known at the end (the return_data of the operation).
    // @param self The pointer to the Account.
    // @param code_len The len of the code
    // @param code The code array
    // @return The updated Account with the code and valid jumpdests set
    func set_code{pedersen_ptr: HashBuiltin*, range_check_ptr}(
        self: model.Account*, code_len: felt, code: felt*
    ) -> model.Account* {
        alloc_locals;
        compute_code_hash(code_len, code);
        let (ap_val) = get_ap();
        let code_hash = cast(ap_val - 2, Uint256*);
        let (valid_jumpdests_start, valid_jumpdests) = Helpers.initialize_jumpdests(code_len, code);
        return new model.Account(
            code_len=code_len,
            code=code,
            code_hash=code_hash,
            storage_start=self.storage_start,
            storage=self.storage,
            transient_storage_start=self.transient_storage_start,
            transient_storage=self.transient_storage,
            valid_jumpdests_start=valid_jumpdests_start,
            valid_jumpdests=valid_jumpdests,
            nonce=self.nonce,
            balance=self.balance,
            selfdestruct=self.selfdestruct,
            created=1,
        );
    }

    // @notice Set the nonce of the Account
    // @param self The pointer to the Account
    // @param nonce The new nonce
    func set_nonce(self: model.Account*, nonce: felt) -> model.Account* {
        return new model.Account(
            code_len=self.code_len,
            code=self.code,
            code_hash=self.code_hash,
            storage_start=self.storage_start,
            storage=self.storage,
            transient_storage_start=self.transient_storage_start,
            transient_storage=self.transient_storage,
            valid_jumpdests_start=self.valid_jumpdests_start,
            valid_jumpdests=self.valid_jumpdests,
            nonce=nonce,
            balance=self.balance,
            selfdestruct=self.selfdestruct,
            created=self.created,
        );
    }

    // @notice Sets an account as created
    func set_created(self: model.Account*, is_created: felt) -> model.Account* {
        return new model.Account(
            code_len=self.code_len,
            code=self.code,
            code_hash=self.code_hash,
            storage_start=self.storage_start,
            storage=self.storage,
            transient_storage_start=self.transient_storage_start,
            transient_storage=self.transient_storage,
            valid_jumpdests_start=self.valid_jumpdests_start,
            valid_jumpdests=self.valid_jumpdests,
            nonce=self.nonce,
            balance=self.balance,
            selfdestruct=self.selfdestruct,
            created=is_created,
        );
    }

    // @notice Set the balance of the Account
    // @param self The pointer to the Account
    // @param balance The new balance
    func set_balance(self: model.Account*, balance: Uint256*) -> model.Account* {
        return new model.Account(
            code_len=self.code_len,
            code=self.code,
            code_hash=self.code_hash,
            storage_start=self.storage_start,
            storage=self.storage,
            transient_storage_start=self.transient_storage_start,
            transient_storage=self.transient_storage,
            valid_jumpdests_start=self.valid_jumpdests_start,
            valid_jumpdests=self.valid_jumpdests,
            nonce=self.nonce,
            balance=balance,
            selfdestruct=self.selfdestruct,
            created=self.created,
        );
    }

    // @notice Register an account for SELFDESTRUCT
    // @dev True means that the account will be erased at the end of the transaction
    // @return The pointer to the updated Account
    func selfdestruct(self: model.Account*) -> model.Account* {
        return new model.Account(
            code_len=self.code_len,
            code=self.code,
            code_hash=self.code_hash,
            storage_start=self.storage_start,
            storage=self.storage,
            transient_storage_start=self.transient_storage_start,
            transient_storage=self.transient_storage,
            valid_jumpdests_start=self.valid_jumpdests_start,
            valid_jumpdests=self.valid_jumpdests,
            nonce=self.nonce,
            balance=self.balance,
            selfdestruct=1,
            created=self.created,
        );
    }

    // @notice Tells if an account has code_len > 0 or nonce > 0
    // @dev See https://github.com/ethereum/execution-specs/blob/3fe6514f2d9d234e760d11af883a47c1263eff51/src/ethereum/shanghai/state.py#L352
    // @param self The pointer to the Account
    // @return TRUE is either nonce > 0 or code_len > 0, FALSE otherwise
    func has_code_or_nonce(self: model.Account*) -> felt {
        if (self.nonce + self.code_len != 0) {
            return TRUE;
        }
        return FALSE;
    }

    func is_storage_warm{pedersen_ptr: HashBuiltin*, range_check_ptr}(
        self: model.Account*, key: Uint256*
    ) -> (model.Account*, felt) {
        alloc_locals;
        local storage: DictAccess* = self.storage;
        let (local storage_addr) = Internals._storage_addr(key);
        let (pointer) = dict_read{dict_ptr=storage}(key=storage_addr);

        tempvar account = new model.Account(
            code_len=self.code_len,
            code=self.code,
            code_hash=self.code_hash,
            storage_start=self.storage_start,
            storage=storage,
            transient_storage_start=self.transient_storage_start,
            transient_storage=self.transient_storage,
            valid_jumpdests_start=self.valid_jumpdests_start,
            valid_jumpdests=self.valid_jumpdests,
            nonce=self.nonce,
            balance=self.balance,
            selfdestruct=self.selfdestruct,
            created=self.created,
        );

        if (pointer != 0) {
            return (account, TRUE);
        }
        return (account, FALSE);
    }

    // @notice Caches the given storage keys by creating an entry in the storage dict of the account.
    // @dev This is used for access list transactions that provide a list of preaccessed keys
    // @param storage_keys_len The number of storage keys to cache.
    // @param storage_keys The pointer to the first storage key.
    func cache_storage_keys{pedersen_ptr: HashBuiltin*, range_check_ptr}(
        self: model.Account*, storage_keys_len: felt, storage_keys: Uint256*
    ) -> model.Account* {
        alloc_locals;
        let storage_ptr = self.storage;
        with storage_ptr {
            Internals._cache_storage_keys(storage_keys_len, storage_keys);
        }
        tempvar self = new model.Account(
            code_len=self.code_len,
            code=self.code,
            code_hash=self.code_hash,
            storage_start=self.storage_start,
            storage=storage_ptr,
            transient_storage_start=self.transient_storage_start,
            transient_storage=self.transient_storage,
            valid_jumpdests_start=self.valid_jumpdests_start,
            valid_jumpdests=self.valid_jumpdests,
            nonce=self.nonce,
            balance=self.balance,
            selfdestruct=self.selfdestruct,
            created=self.created,
        );
        return self;
    }

    func compute_code_hash{
        range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*
    }(code_len: felt, code: felt*) -> Uint256 {
        alloc_locals;
        if (code_len == 0) {
            // see https://eips.ethereum.org/EIPS/eip-1052
            let empty_code_hash = Uint256(
                304396909071904405792975023732328604784, 262949717399590921288928019264691438528
            );
            return empty_code_hash;
        }
        let code_hash = keccak(code_len, code);
        return code_hash;
    }
}

namespace Internals {
    // @notice Compute the storage address of the given key
    // @dev    Just the hash of low and high to get a unique random felt key
    func _storage_addr{pedersen_ptr: HashBuiltin*}(key: Uint256*) -> (res: felt) {
        let (res) = hash2{hash_ptr=pedersen_ptr}(key.low, key.high);
        return (res=res);
    }

    // TODO: fixme value shouldn't be always 0
    func _cache_storage_keys{pedersen_ptr: HashBuiltin*, range_check_ptr, storage_ptr: DictAccess*}(
        storage_keys_len: felt, storage_keys: Uint256*
    ) {
        alloc_locals;
        if (storage_keys_len == 0) {
            return ();
        }

        let key = storage_keys;
        let (local storage_addr) = Internals._storage_addr(key);
        tempvar value_ptr = new Uint256(0, 0);
        dict_write{dict_ptr=storage_ptr}(key=storage_addr, new_value=cast(value_ptr, felt));

        return _cache_storage_keys(storage_keys_len - 1, storage_keys + Uint256.SIZE);
    }
}
