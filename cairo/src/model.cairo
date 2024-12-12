// StarkWare dependencies
from starkware.cairo.common.dict import DictAccess
from starkware.cairo.common.uint256 import Uint256

namespace model {
    // @notice Represents the cost and size of a memory expansion operation.
    // @param cost The cost of the memory expansion operation.
    // @param new_words_len The number of words in the memory post-expansion.
    struct MemoryExpansion {
        cost: felt,
        new_words_len: felt,
    }

    // @notice: Represents an optional value.
    // @param is_some A boolean indicating whether the value is present.
    // @param value The value (if applicable).
    struct Option {
        is_some: felt,
        value: felt,
    }

    // @notice Info: https://www.evm.codes/about#stack
    // @notice Stack with a 1024 items maximum size. Each item is a 256 bits word. The stack is used by most
    // @notice opcodes to consume their parameters from.
    // @dev The dict stores a pointer to the word (a Uint256).
    // @param size The size of the Stack.
    // @param dict_ptr_start pointer to a DictAccess array used to store the stack's value at a given index.
    // @param dict_ptr pointer to the end of the DictAccess array.
    struct Stack {
        dict_ptr_start: DictAccess*,
        dict_ptr: DictAccess*,
        size: felt,
    }

    // @notice info: https://www.evm.codes/about#memory
    // @notice Transient memory maintained by the EVM during an execution which doesn't persist
    // @notice between transactions.
    // @param word_dict_start pointer to a DictAccess used to store the memory's value at a given index.
    // @param word_dict pointer to the end of the DictAccess array.
    // @param words_len number of words (bytes32).
    struct Memory {
        word_dict_start: DictAccess*,
        word_dict: DictAccess*,
        words_len: felt,
    }

    // @dev In Cairo Zero, dict are list of DictAccess, ie that they can contain only felts. For having
    //      dict of structs, we store in the dict pointers to the struct. List of structs are just list of
    //      felt with inlined structs. Hence one has eventually
    //      accounts := Dict<starknet_address, Account*>
    //      events := List<Event>
    struct State {
        accounts_start: DictAccess*,
        accounts: DictAccess*,
        events_len: felt,
        events: Event*,
    }

    // @notice The struct representing an EVM account.
    // @dev We don't put the balance here to avoid loading the whole Account just for sending ETH
    // @dev The address is a tuple (starknet, evm) for step-optimization purposes:
    // we can compute the starknet only once.
    struct Account {
        code_len: felt,
        code: felt*,
        code_hash: Uint256*,
        storage_start: DictAccess*,
        storage: DictAccess*,
        transient_storage_start: DictAccess*,
        transient_storage: DictAccess*,
        valid_jumpdests_start: DictAccess*,
        valid_jumpdests: DictAccess*,
        nonce: felt,
        balance: Uint256*,
        selfdestruct: felt,
        created: felt,
    }

    // @notice The struct representing an EVM event.
    // @dev The topics are indeed a first felt for the emitting EVM account, followed by a list of Uint256
    struct Event {
        topics_len: felt,
        topics: felt*,
        data_len: felt,
        data: felt*,
    }

    // @dev A struct to save Starknet native ETH transfers to be made when finalizing a tx
    struct Transfer {
        sender: felt,
        recipient: felt,
        amount: Uint256,
    }

    // @notice info: https://www.evm.codes/about#calldata
    // @notice Struct storing data related to a call.
    // @dev All Message fields are constant during a given call.
    // @param bytecode The executed bytecode.
    // @param bytecode_len The length of bytecode.
    // @param calldata byte The space where the data parameter of a transaction or call is held.
    // @param calldata_len The length of calldata.
    // @param value The amount of native token to transfer.
    // @param parent The parent context of the current execution context, can be empty.
    // @param address The address of the current EVM account. Note that the bytecode may not be the one
    //        of the account in case of a CALLCODE or DELEGATECALL
    // @param code_address The EVM address the bytecode of the message is taken from.
    // @param read_only if set to true, context cannot do any state modifying instructions or send ETH in the sub context.
    // @param is_create if set to true, the call context is a CREATEs or deploy execution
    // @param depth The depth of the current execution context.
    struct Message {
        bytecode: felt*,
        bytecode_len: felt,
        valid_jumpdests_start: DictAccess*,
        valid_jumpdests: DictAccess*,
        calldata: felt*,
        calldata_len: felt,
        value: Uint256*,
        caller: felt,
        parent: Parent*,
        address: felt,
        code_address: felt,
        read_only: felt,
        is_create: felt,
        depth: felt,
        env: Environment*,
        initial_state: State*,
    }

    // @dev Stores all data relevant to the current execution context.
    // @param message The call context data.
    // @param return_data_len The return_data length.
    // @param return_data The region used to return a value after a call.
    // @param program_counter The keep track of the current position in the program as it is being executed.
    // @param stopped A boolean that state if the current execution is halted.
    // @param gas_left The gas consumed by the current state of the execution.
    // @param reverted A code indicating whether the EVM is reverted or not.
    // can be either 0 - not reverted, Errors.REVERTED or Errors.EXCEPTIONAL_HALT
    struct EVM {
        message: Message*,
        return_data_len: felt,
        return_data: felt*,
        program_counter: felt,
        stopped: felt,
        gas_left: felt,
        gas_refund: felt,
        reverted: felt,
    }

    // @notice Store all environment data relevant to the current execution context.
    // @param origin The origin of the transaction.
    // @param gas_price The gas price for the call.
    // @param chain_id The chain id of the current block.
    // @param prev_randao The previous RANDAO value.
    // @param block_number The block number of the current block.
    // @param block_gas_limit The gas limit for the current block.
    // @param block_timestamp The timestamp of the current block.
    // @param coinbase The address of the miner of the current block.
    // @param base_fee The basefee of the current block.
    // @param block_hashes The block hashes of the last 256 blocks.
    struct Environment {
        origin: felt,
        gas_price: felt,
        chain_id: felt,
        prev_randao: Uint256,
        block_number: felt,
        block_gas_limit: felt,
        block_timestamp: felt,
        coinbase: felt,
        base_fee: felt,
        block_hashes: Uint256*,
        excess_blob_gas: Option,
    }

    // @dev The parent EVM struct is used to store the parent EVM context of the current execution context.
    struct Parent {
        evm: EVM*,
        stack: Stack*,
        memory: Memory*,
        state: State*,
    }

    // @dev Stores the constant data of an opcode
    // @param number The opcode number
    // @param gas The minimum gas used by the opcode (not including possible dynamic gas)
    // @param stack_input The number of inputs popped from the stack.
    // @param stack_size_min The minimal size of the Stack for this opcode.
    // @param stack_size_diff The difference between the stack size after and before
    struct Opcode {
        number: felt,
        gas: felt,
        stack_input: felt,
        stack_size_min: felt,
        stack_size_diff: felt,
    }

    // @notice A normalized Ethereum transaction
    // @dev See https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1559.md
    struct Transaction {
        signer_nonce: felt,
        gas_limit: felt,
        max_priority_fee_per_gas: felt,
        max_fee_per_gas: felt,
        destination: Option,
        amount: Uint256,
        payload_len: felt,
        payload: felt*,
        access_list_len: felt,
        access_list: felt*,
        chain_id: Option,
    }

    // @notice A struct representing the header of an Eth block.
    struct BlockHeader {
        parent_hash: Uint256,
        ommers_hash: Uint256,
        coinbase: felt,
        state_root: Uint256,
        transactions_root: Uint256,
        receipt_root: Uint256,
        withdrawals_root: Option,
        bloom: felt*,
        difficulty: Uint256,
        number: felt,
        gas_limit: felt,
        gas_used: felt,
        timestamp: felt,
        mix_hash: Uint256,
        nonce: felt,
        base_fee_per_gas: Option,
        blob_gas_used: Option,
        excess_blob_gas: Option,
        parent_beacon_block_root: Option,
        requests_root: Option,
        extra_data_len: felt,
        extra_data: felt*,
    }

    // @notice A struct representing an encoded Ethereum transaction.
    // @dev The RLP is the Ethereum unsigned transaction, followed by the signature.
    // @param rlp_len The length of the RLP encoded transaction.
    // @param rlp The RLP-encoded unsigned data of the transaction.
    // @param signature_len The length of the signature.
    // @param signature The signature.
    // @param sender The sender of the transaction.
    struct TransactionEncoded {
        rlp_len: felt,
        rlp: felt*,
        signature_len: felt,
        signature: felt*,
        sender: felt,
    }

    // @notice A struct representing an Ethereum block.
    // @param header The header of the block.
    // @param transactions The transactions in the block.
    struct Block {
        block_header: BlockHeader*,
        transactions_len: felt,
        transactions: TransactionEncoded*,
    }
}
