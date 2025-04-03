from ethereum_types.numeric import Uint, bool, SetUint, U256
from ethereum.cancun.state import State, TransientStorage
from ethereum.cancun.blocks import Log, TupleLog, TupleLogStruct
from ethereum.cancun.fork_types import SetAddress, SetTupleAddressBytes32
from ethereum.exceptions import EthereumException
from ethereum_types.bytes import Bytes, OptionalBytes
from ethereum.cancun.vm.stack import Stack
from ethereum.cancun.vm.memory import Memory
from ethereum.cancun.vm.env_impl import Environment, EnvironmentStruct
from ethereum.cancun.fork_types import Address, OptionalAddress
from ethereum.cancun.transactions_types import To

using OptionalEvm = Evm;

struct Message {
    value: MessageStruct*,
}

struct EvmStruct {
    pc: Uint,
    stack: Stack,
    memory: Memory,
    code: Bytes,
    gas_left: Uint,
    env: Environment,
    valid_jump_destinations: SetUint,
    logs: TupleLog,
    refund_counter: felt,
    running: bool,
    message: Message,
    output: Bytes,
    accounts_to_delete: SetAddress,
    touched_accounts: SetAddress,
    return_data: Bytes,
    error: EthereumException*,
    accessed_addresses: SetAddress,
    accessed_storage_keys: SetTupleAddressBytes32,
}

struct Evm {
    value: EvmStruct*,
}

struct MessageStruct {
    caller: Address,
    target: To,
    current_target: Address,
    gas: Uint,
    value: U256,
    data: Bytes,
    code_address: OptionalAddress,
    code: Bytes,
    depth: Uint,
    should_transfer_value: bool,
    is_static: bool,
    accessed_addresses: SetAddress,
    accessed_storage_keys: SetTupleAddressBytes32,
    parent_evm: OptionalEvm,
}

// In a specific file to avoid circular imports
namespace EvmImpl {
    func set_pc{evm: Evm}(new_pc: Uint) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=new_pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_stack{evm: Evm}(new_stack: Stack) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=new_stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_memory{evm: Evm}(new_memory: Memory) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=new_memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_code{evm: Evm}(new_code: Bytes) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=OptionalBytes(new_code.value),
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_gas_left{evm: Evm}(new_gas_left: Uint) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=new_gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_env{evm: Evm}(new_env: Environment) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=new_env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_valid_jump_destinations{evm: Evm}(new_valid_jump_destinations: SetUint) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=new_valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_logs{evm: Evm}(new_logs: TupleLog) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=new_logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_refund_counter{evm: Evm}(new_refund_counter: felt) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=new_refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_running{evm: Evm}(new_running: bool) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=new_running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_message{evm: Evm}(new_message: Message) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=new_message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_output{evm: Evm}(new_output: Bytes) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=new_output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_accounts_to_delete{evm: Evm}(new_accounts_to_delete: SetAddress) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=new_accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_touched_accounts{evm: Evm}(new_touched_accounts: SetAddress) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=new_touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_return_data{evm: Evm}(new_return_data: Bytes) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=new_return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_error{evm: Evm}(new_error: EthereumException*) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=new_error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_accessed_addresses{evm: Evm}(new_accessed_addresses: SetAddress) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=new_accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_accessed_storage_keys{evm: Evm}(new_accessed_storage_keys: SetTupleAddressBytes32) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=evm.value.pc,
                stack=evm.value.stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=new_accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_pc_stack{evm: Evm}(new_pc: Uint, new_stack: Stack) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=new_pc,
                stack=new_stack,
                memory=evm.value.memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }

    func set_pc_stack_memory{evm: Evm}(new_pc: Uint, new_stack: Stack, new_memory: Memory) {
        tempvar evm = Evm(
            new EvmStruct(
                pc=new_pc,
                stack=new_stack,
                memory=new_memory,
                code=evm.value.code,
                gas_left=evm.value.gas_left,
                env=evm.value.env,
                valid_jump_destinations=evm.value.valid_jump_destinations,
                logs=evm.value.logs,
                refund_counter=evm.value.refund_counter,
                running=evm.value.running,
                message=evm.value.message,
                output=evm.value.output,
                accounts_to_delete=evm.value.accounts_to_delete,
                touched_accounts=evm.value.touched_accounts,
                return_data=evm.value.return_data,
                error=evm.value.error,
                accessed_addresses=evm.value.accessed_addresses,
                accessed_storage_keys=evm.value.accessed_storage_keys,
            ),
        );
        return ();
    }
}
