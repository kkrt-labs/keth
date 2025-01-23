from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin, PoseidonBuiltin
from starkware.cairo.common.default_dict import default_dict_new
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.math_cmp import is_nn

from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import Uint, bool
from ethereum.cancun.blocks import TupleLog, TupleLogStruct, Log
from ethereum.cancun.fork_types import SetAddress
from ethereum.cancun.fork_types import SetAddressStruct, SetAddressDictAccess
from ethereum.cancun.vm import Evm, EvmStruct, Message, Environment, EvmImpl
from ethereum.cancun.vm.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import Revert
from ethereum.cancun.vm.instructions import op_implementation
from ethereum.cancun.vm.memory import Memory, MemoryStruct, Bytes1DictAccess
from ethereum.cancun.vm.runtime import get_valid_jump_destinations
from ethereum.cancun.vm.stack import Stack, StackStruct, StackDictAccess

from src.utils.dict import dict_new_empty

func execute_code{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(message: Message, env: Environment) -> Evm {
    alloc_locals;

    // Get valid jump destinations
    let valid_jumpdests = get_valid_jump_destinations(message.value.code);
    // Create empty stack
    let (dict_start: DictAccess*) = default_dict_new(0);
    let dict_ptr = dict_start;
    tempvar empty_stack = Stack(
        new StackStruct(
            dict_ptr_start=cast(dict_start, StackDictAccess*),
            dict_ptr=cast(dict_ptr, StackDictAccess*),
            len=0,
        ),
    );
    // Create empty memory
    let (dict_start: DictAccess*) = default_dict_new(0);
    let dict_ptr = dict_start;
    tempvar empty_memory = Memory(
        new MemoryStruct(
            dict_ptr_start=cast(dict_start, Bytes1DictAccess*),
            dict_ptr=cast(dict_ptr, Bytes1DictAccess*),
            len=0,
        ),
    );
    // Create empty Logs
    let (empty_logs: Log*) = alloc();
    tempvar tuple_log_struct = TupleLog(new TupleLogStruct(data=empty_logs, len=0));
    // Create empty accounts_to_delete and touched_accounts
    let (dict_start: DictAccess*) = default_dict_new(0);
    let dict_ptr = dict_start;
    tempvar empty_accounts_to_delete = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(dict_start, SetAddressDictAccess*),
            dict_ptr=cast(dict_ptr, SetAddressDictAccess*),
        ),
    );
    let (dict_start: DictAccess*) = default_dict_new(0);
    let dict_ptr = dict_start;
    tempvar empty_touched_accounts = SetAddress(
        new SetAddressStruct(
            dict_ptr_start=cast(dict_start, SetAddressDictAccess*),
            dict_ptr=cast(dict_ptr, SetAddressDictAccess*),
        ),
    );

    // Initialize EVM state
    tempvar evm = Evm(
        new EvmStruct(
            pc=Uint(0),
            stack=empty_stack,
            memory=empty_memory,
            code=message.value.code,
            gas_left=message.value.gas,
            env=env,
            valid_jump_destinations=valid_jumpdests,
            logs=tuple_log_struct,
            refund_counter=0,
            running=bool(1),
            message=message,
            output=Bytes(new BytesStruct(cast(0, felt*), 0)),
            accounts_to_delete=empty_accounts_to_delete,
            touched_accounts=empty_touched_accounts,
            return_data=Bytes(new BytesStruct(cast(0, felt*), 0)),
            error=cast(0, EthereumException*),
            accessed_addresses=message.value.accessed_addresses,
            accessed_storage_keys=message.value.accessed_storage_keys,
        ),
    );

    // TODO: Handle precompiled contracts

    // Execute bytecode recursively
    return _execute_code(evm);
}

func _execute_code{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
}(evm: Evm) -> Evm {
    alloc_locals;

    // Base case: EVM not running or PC >= code length
    if (evm.value.running.value == FALSE) {
        return evm;
    }
    let is_pc_ge_code_len = is_nn(evm.value.pc.value - evm.value.code.value.len);
    if (is_pc_ge_code_len != FALSE) {
        return evm;
    }

    // Execute the opcode and handle any errors
    let opcode = [evm.value.code.value.data + evm.value.pc.value];
    with evm {
        let err = op_implementation(opcode);
        if (cast(err, felt) != 0) {
            if (err.value == Revert) {
                EvmImpl.set_error(err);
                return evm;
            }

            EvmImpl.set_gas_left(Uint(0));
            let (output_bytes: felt*) = alloc();
            tempvar output = Bytes(new BytesStruct(output_bytes, 0));
            EvmImpl.set_output(output);
            EvmImpl.set_error(err);
            return evm;
        }
    }

    // Recursive call to continue execution
    return _execute_code(evm);
}
