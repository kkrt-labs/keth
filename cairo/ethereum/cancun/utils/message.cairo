from ethereum.cancun.vm import Message, MessageStruct, EvmStruct, Evm
from ethereum.cancun.vm import BlockEnvironment, TransactionEnvironment
from ethereum.cancun.fork_types import (
    Address,
    OptionalAddress,
    SetAddress,
    SetAddressStruct,
    SetAddressDictAccess,
)
from ethereum_types.bytes import Bytes, BytesStruct, Bytes20
from ethereum_types.numeric import Uint, bool
from ethereum.cancun.state import get_account, State, StateStruct, get_account_code
from ethereum.cancun.utils.address import compute_contract_address
from ethereum.cancun.transactions import Transaction
from ethereum.cancun.transactions_types import get_data, get_to, get_value
from ethereum.cancun.vm.env_impl import BlockEnvImpl

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict_access import DictAccess

from legacy.utils.dict import hashdict_write, dict_write

const PRECOMPILED_ADDRESSES_SIZE = 10;

func prepare_message{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    block_env: BlockEnvironment,
    tx_env: TransactionEnvironment,
}(tx: Transaction) -> Message {
    alloc_locals;

    let fp_and_pc = get_fp_and_pc();
    local __fp__: felt* = fp_and_pc.fp_val;

    let access_list_addresses = tx_env.value.access_list_addresses;
    let access_list_addresses_ptr_start = access_list_addresses.value.dict_ptr_start;
    let access_list_addresses_ptr = cast(access_list_addresses.value.dict_ptr, DictAccess*);
    hashdict_write{dict_ptr=access_list_addresses_ptr}(1, &tx_env.value.origin.value, 1);
    track_precompiles{dict_ptr=access_list_addresses_ptr}();

    let to = get_to(tx);
    let data = get_data(tx);

    let state = block_env.value.state;
    if (cast(to.value.bytes0, felt) != 0) {
        let caller_account = get_account{state=state}(tx_env.value.origin);
        // wont't underflow: the nonce of the caller is always incremented by 1 before `prepare_message`.
        let nonce = Uint(caller_account.value.nonce.value - 1);
        let current_target = compute_contract_address(tx_env.value.origin, nonce);

        let (empty_data: felt*) = alloc();
        tempvar empty_bytes_struct = new BytesStruct(empty_data, 0);
        tempvar state = state;
        tempvar msg_data = Bytes(empty_bytes_struct);
        tempvar code = data;
        tempvar current_target = current_target;
        tempvar code_address = OptionalAddress(cast(0, felt*));
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    } else {
        // Case Address
        tempvar current_target = Address(to.value.address.value);
        tempvar msg_data = data;
        let target_account = get_account{state=state}(current_target);
        tempvar code_address = OptionalAddress(new Address(current_target.value));
        let target_code = get_account_code{state=state}(current_target, target_account);
        tempvar state = state;
        tempvar msg_data = msg_data;
        tempvar code = target_code;
        tempvar current_target = current_target;
        tempvar code_address = code_address;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
    }
    let state_ = cast([ap - 9], StateStruct*);
    let msg_data = Bytes(cast([ap - 8], BytesStruct*));
    let code = Bytes(cast([ap - 7], BytesStruct*));
    let current_target = Bytes20([ap - 6]);
    let code_address_ = cast([ap - 5], Address*);
    let range_check_ptr = [ap - 4];
    let bitwise_ptr = cast([ap - 3], BitwiseBuiltin*);
    let keccak_ptr = cast([ap - 2], felt*);
    let poseidon_ptr = cast([ap - 1], PoseidonBuiltin*);

    let state = State(state_);
    BlockEnvImpl.set_state{block_env=block_env}(state);
    tempvar current_target_ = new current_target;
    tempvar code_address = OptionalAddress(code_address_);

    hashdict_write{dict_ptr=access_list_addresses_ptr}(1, current_target_, 1);
    tempvar accessed_addresses = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(access_list_addresses_ptr_start, SetAddressDictAccess*),
            dict_ptr=cast(access_list_addresses_ptr, SetAddressDictAccess*),
        ),
    );

    let tx_value = get_value(tx);
    tempvar res = Message(
        new MessageStruct(
            block_env=block_env,
            tx_env=tx_env,
            caller=tx_env.value.origin,
            target=to,
            current_target=current_target,
            gas=tx_env.value.gas,
            value=tx_value,
            data=msg_data,
            code_address=code_address,
            code=code,
            depth=Uint(0),
            should_transfer_value=bool(1),
            is_static=bool(0),
            accessed_addresses=accessed_addresses,
            accessed_storage_keys=tx_env.value.access_list_storage_keys,
            parent_evm=Evm(cast(0, EvmStruct*)),
        ),
    );

    return res;
}

func track_precompiles{dict_ptr: DictAccess*}() {
    dict_write(0x100000000000000000000000000000000000000, 1);
    dict_write(0x200000000000000000000000000000000000000, 1);
    dict_write(0x300000000000000000000000000000000000000, 1);
    dict_write(0x400000000000000000000000000000000000000, 1);
    dict_write(0x500000000000000000000000000000000000000, 1);
    dict_write(0x600000000000000000000000000000000000000, 1);
    dict_write(0x700000000000000000000000000000000000000, 1);
    dict_write(0x800000000000000000000000000000000000000, 1);
    dict_write(0x900000000000000000000000000000000000000, 1);
    dict_write(0xa00000000000000000000000000000000000000, 1);
    return ();
}
