// This file implements the EOA delegation mechanism as specified in EIP-7702.
// Link: https://eips.ethereum.org/EIPS/eip-7702

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, ModBuiltin
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.registers import get_label_location
from cairo_ec.curve.secp256k1 import secp256k1

from ethereum_types.bytes import Bytes, BytesStruct
from ethereum_types.numeric import U64, U256, U256Struct, Uint, bool
from ethereum.crypto.elliptic_curve import secp256k1_recover, public_key_point_to_eth_address
from ethereum.crypto.hash import Hash32, keccak256
from ethereum.exceptions import EthereumException, InvalidSignatureError
from ethereum.prague.utils.constants import U256_ZERO
from ethereum.prague.vm.env_impl import BlockEnvImpl
from ethereum.prague.vm.evm_impl import Evm, Message, MessageImpl, EvmImpl
from ethereum.prague.vm.gas import GasConstants
from ethereum.prague.fork_types import (
    Address,
    Authorization,
    OptionalAddress,
    SetAddress,
    TupleAuthorization,
)
from ethereum.prague.state import (
    account_exists,
    get_account,
    get_account_code,
    increment_nonce,
    set_code,
    State,
)
from ethereum_rlp.rlp import _encode_uint, _encode_u256, _encode_address, _encode_prefix_len
from ethereum_rlp.rlp import PREFIX_LEN_MAX
from ethereum.utils.hash_dicts import set_address_contains, set_address_add
from ethereum.utils.numeric import U256_le, U256__eq__, U256_sub, U256_add
from legacy.utils.bytes import bytes_to_felt_le, felt_to_bytes20_little
from cairo_core.control_flow import raise

// Constants
const SET_CODE_TX_MAGIC_LEN = 1;
const SET_CODE_TX_MAGIC_BYTE_0 = 0x05;
const EOA_DELEGATION_MARKER_LEN = 3;
const EOA_DELEGATION_MARKER_BYTE_0 = 0xEF;
const EOA_DELEGATION_MARKER_BYTE_1 = 0x01;
const EOA_DELEGATION_MARKER_BYTE_2 = 0x00;
const EOA_DELEGATED_CODE_LENGTH = 23;
const PER_EMPTY_ACCOUNT_COST_LOW = 25000;
const PER_EMPTY_ACCOUNT_COST_HIGH = 0;
const PER_AUTH_BASE_COST_LOW = 12500;
const PER_AUTH_BASE_COST_HIGH = 0;
const U64_MAX_VALUE = 0xffffffffffffffff;

// @notice Whether the code is a valid delegation designation.
// @param code The account code to check.
// @return is_valid True if the code is a valid delegation, False otherwise.
func is_valid_delegation{range_check_ptr}(code: Bytes) -> bool {
    alloc_locals;
    if (code.value.len != EOA_DELEGATED_CODE_LENGTH) {
        let is_valid = bool(FALSE);
        return is_valid;
    }
    if (code.value.data[0] != EOA_DELEGATION_MARKER_BYTE_0) {
        let is_valid = bool(FALSE);
        return is_valid;
    }
    if (code.value.data[1] != EOA_DELEGATION_MARKER_BYTE_1) {
        let is_valid = bool(FALSE);
        return is_valid;
    }
    if (code.value.data[2] != EOA_DELEGATION_MARKER_BYTE_2) {
        let is_valid = bool(FALSE);
        return is_valid;
    }
    let is_valid = bool(TRUE);
    return is_valid;
}

// @notice Get the address to which the code delegates.
// @param code The account code to get the delegated address from.
// @return delegated_address The address of the delegated code.
func get_delegated_code_address{range_check_ptr}(code: Bytes) -> OptionalAddress {
    alloc_locals;
    let is_valid = is_valid_delegation(code);
    if (is_valid.value == FALSE) {
        let delegated_address = OptionalAddress(cast(0, felt*));
        return delegated_address;
    }
    let addr_felt = bytes_to_felt_le(20, code.value.data + EOA_DELEGATION_MARKER_LEN);
    tempvar delegated_address = OptionalAddress(new addr_felt);
    return delegated_address;
}

// @notice Recover the authority address from the authorization.
// @param authorization The authorization to recover the authority from..
// @return authority The recovered authority address.
// @return err An EthereumException pointer if signature recovery fails, otherwise a null pointer.
func recover_authority{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
}(authorization: Authorization) -> (authority: Address, err: EthereumException*) {
    alloc_locals;
    let y_parity_felt = cast(authorization.value.y_parity.value, felt);
    if (y_parity_felt != 0 and y_parity_felt != 1) {
        tempvar err_ptr = new EthereumException(InvalidSignatureError);
        return (authority=Address(0), err=err_ptr);
    }
    let r_u256 = authorization.value.r;
    let (zero_ptr) = get_label_location(U256_ZERO);
    let r_eq_zero = U256__eq__(r_u256, U256(cast(zero_ptr, U256Struct*)));
    if (r_eq_zero.value == TRUE) {
        tempvar err_ptr = new EthereumException(InvalidSignatureError);
        return (authority=Address(0), err=err_ptr);
    }
    tempvar SECP256K1N = U256(new U256Struct(low=secp256k1.N_LOW_128, high=secp256k1.N_HIGH_128));
    let r_ge_n = U256_le(SECP256K1N, r_u256);
    if (r_ge_n.value == TRUE) {
        tempvar err_ptr = new EthereumException(InvalidSignatureError);
        return (authority=Address(0), err=err_ptr);
    }
    let s_u256 = authorization.value.s;
    let (zero_ptr) = get_label_location(U256_ZERO);
    let s_eq_zero = U256__eq__(s_u256, U256(cast(zero_ptr, U256Struct*)));
    if (s_eq_zero.value == TRUE) {
        tempvar err_ptr = new EthereumException(InvalidSignatureError);
        return (authority=Address(0), err=err_ptr);
    }
    tempvar secp256k1n_div_2 = U256(
        new U256Struct(low=secp256k1.N_DIVIDED_BY_2_LOW_128, high=secp256k1.N_DIVIDED_BY_2_HIGH_128)
    );
    let s_gt_n_div_2 = U256_le(secp256k1n_div_2, s_u256);
    if (s_gt_n_div_2.value == TRUE) {
        tempvar err_ptr = new EthereumException(InvalidSignatureError);
        return (authority=Address(0), err=err_ptr);
    }

    // Encode the tuple (chain_id, address, nonce) directly using low-level RLP encoding
    // This matches Python's rlp.encode((authorization.chain_id, authorization.address, authorization.nonce))
    let (local dst) = alloc();
    let body_ptr = dst + PREFIX_LEN_MAX;

    // Encode chain_id as U256
    let chain_id_len = _encode_u256(body_ptr, authorization.value.chain_id);
    let body_ptr = body_ptr + chain_id_len;

    // Encode address
    let address_len = _encode_address(body_ptr, authorization.value.address);
    let body_ptr = body_ptr + address_len;

    // Encode nonce as U64 (convert to Uint first)
    tempvar auth_nonce_uint = Uint(authorization.value.nonce.value);
    let nonce_len = _encode_uint(body_ptr, auth_nonce_uint.value);
    let body_ptr = body_ptr + nonce_len;

    // Calculate body length and encode prefix
    let body_len = body_ptr - dst - PREFIX_LEN_MAX;
    let body_ptr = dst + PREFIX_LEN_MAX;
    let prefix_len = _encode_prefix_len(body_ptr, body_len);

    // Create the final message: SET_CODE_TX_MAGIC + rlp_encoded_tuple
    let rlp_encoded_len = prefix_len + body_len;
    let (message_data: felt*) = alloc();
    assert message_data[0] = SET_CODE_TX_MAGIC_BYTE_0;
    memcpy(message_data + 1, body_ptr - prefix_len, rlp_encoded_len);
    tempvar message_to_hash_bytes = Bytes(
        new BytesStruct(data=message_data, len=1 + rlp_encoded_len)
    );

    let signing_hash_u256 = keccak256(message_to_hash_bytes);
    tempvar signing_hash_for_recover = Hash32(signing_hash_u256.value);
    tempvar v_param = U256(new U256Struct(low=authorization.value.y_parity.value, high=0));

    let (pk_x, pk_y, recovery_err) = secp256k1_recover(
        r=r_u256, s=s_u256, v=v_param, msg_hash=signing_hash_for_recover
    );
    if (cast(recovery_err, felt) != 0) {
        return (authority=Address(0), err=recovery_err);
    }
    let derived_address = public_key_point_to_eth_address(pk_x, pk_y);
    return (authority=derived_address, err=cast(0, EthereumException*));
}

// @notice Get the delegation address, code, and the cost of access from the address.
// @param evm The current EVM context
// @param address The execution frame.
// @return is_delegated True if the account at `address` is a delegation, False otherwise.
// @return effective_address The address from which code is ultimately executed (either `address` or the delegated address).
// @return code The code to be executed.
// @return access_gas_cost The gas cost associated with accessing the delegated code (0 if not delegated or already warm).
// @return err An EthereumException pointer if an error occurs, otherwise a null pointer.
func access_delegation{
    range_check_ptr, poseidon_ptr: PoseidonBuiltin*, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: felt*
}(evm: Evm, address: Address) -> (
    is_delegated: bool,
    effective_address: Address,
    code: Bytes,
    access_gas_cost: Uint,
    err: EthereumException*,
) {
    alloc_locals;
    let block_env = evm.value.message.value.block_env;
    let state = block_env.value.state;
    let account = get_account{state=state}(address);
    let initial_code = get_account_code{state=state}(address, account);
    let is_valid = is_valid_delegation(initial_code);
    if (is_valid.value == FALSE) {
        BlockEnvImpl.set_state{block_env=block_env}(state);
        EvmImpl.set_block_env{evm=evm}(block_env);
        return (bool(FALSE), address, initial_code, Uint(0), cast(0, EthereumException*));
    }
    let delegated_optional_address = get_delegated_code_address(initial_code);
    let delegated_address_ptr = cast(delegated_optional_address.value, Address*);
    tempvar delegated_address = Address([delegated_optional_address.value]);
    let accessed_addresses = evm.value.accessed_addresses;
    let is_warmed = set_address_contains{set=accessed_addresses}(delegated_address);
    local gas_cost_val: felt;
    if (is_warmed != 0) {
        gas_cost_val = GasConstants.GAS_WARM_ACCESS;
        tempvar range_check_ptr = range_check_ptr;
        tempvar accessed_addresses = accessed_addresses;
    } else {
        set_address_add{set_address=accessed_addresses}(delegated_address);
        gas_cost_val = GasConstants.GAS_COLD_ACCOUNT_ACCESS;
        tempvar range_check_ptr = range_check_ptr;
        tempvar accessed_addresses = accessed_addresses;
    }
    tempvar accessed_addresses = accessed_addresses;
    let delegated_account = get_account{state=state}(delegated_address);
    let final_code = get_account_code{state=state}(delegated_address, delegated_account);
    BlockEnvImpl.set_state{block_env=block_env}(state);
    EvmImpl.set_block_env{evm=evm}(block_env);
    EvmImpl.set_accessed_addresses{evm=evm}(accessed_addresses);
    return (
        is_delegated=bool(TRUE),
        effective_address=delegated_address,
        code=final_code,
        access_gas_cost=Uint(gas_cost_val),
        err=cast(0, EthereumException*),
    );
}

func _set_delegation_loop{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    state: State,
    accessed_addresses: SetAddress,
}(
    authorizations: TupleAuthorization,
    current_idx: felt,
    refund_counter: U256,
    block_env_chain_id: U64,
) -> U256 {
    alloc_locals;

    if (current_idx == authorizations.value.len) {
        return refund_counter;
    }

    let auth = authorizations.value.data[current_idx];

    // Skip if chain_id does not match current block or is not zero
    tempvar chain_id_u256 = U256(new U256Struct(low=block_env_chain_id.value, high=0));
    let chain_id_matches_block = U256__eq__(auth.value.chain_id, chain_id_u256);
    let (zero_ptr) = get_label_location(U256_ZERO);
    let chain_id_eq_zero = U256__eq__(auth.value.chain_id, U256(cast(zero_ptr, U256Struct*)));
    if (chain_id_matches_block.value == FALSE and chain_id_eq_zero.value == FALSE) {
        return _set_delegation_loop(
            authorizations, current_idx + 1, refund_counter, block_env_chain_id
        );
    }

    let nonce_ge_max = is_le_felt(U64_MAX_VALUE, auth.value.nonce.value);
    if (nonce_ge_max != FALSE) {
        return _set_delegation_loop(
            authorizations, current_idx + 1, refund_counter, block_env_chain_id
        );
    }

    let (authority, rec_err) = recover_authority(auth);
    // If authority recovery fails, skip this authorization and continue with the next
    if (cast(rec_err, felt) != 0) {
        return _set_delegation_loop(
            authorizations, current_idx + 1, refund_counter, block_env_chain_id
        );
    }

    set_address_add{set_address=accessed_addresses}(authority);

    let authority_account = get_account{state=state}(authority);
    let authority_code = get_account_code{state=state}(authority, authority_account);

    // Skip if authority already has non-delegation code
    if (authority_code.value.len != 0) {
        let is_valid_auth_code = is_valid_delegation(authority_code);
        if (is_valid_auth_code.value == FALSE) {
            return _set_delegation_loop(
                authorizations, current_idx + 1, refund_counter, block_env_chain_id
            );
        } else {
            tempvar range_check_ptr = range_check_ptr;
        }
    } else {
        tempvar range_check_ptr = range_check_ptr;
    }

    let authority_nonce = authority_account.value.nonce;
    // Skip if authority's current nonce does not match the nonce in the authorization
    if (authority_nonce.value != auth.value.nonce.value) {
        return _set_delegation_loop(
            authorizations, current_idx + 1, refund_counter, block_env_chain_id
        );
    }

    local refund_counter_after_current_auth: U256;
    let exists = account_exists{state=state}(authority);
    if (exists.value != FALSE) {
        tempvar per_empty_cost = U256(
            new U256Struct(low=PER_EMPTY_ACCOUNT_COST_LOW, high=PER_EMPTY_ACCOUNT_COST_HIGH)
        );
        tempvar per_auth_cost = U256(
            new U256Struct(low=PER_AUTH_BASE_COST_LOW, high=PER_AUTH_BASE_COST_HIGH)
        );
        let refund_amount = U256_sub(per_empty_cost, per_auth_cost);
        let current_refund_plus_new = U256_add(refund_counter, refund_amount);
        assert refund_counter_after_current_auth = current_refund_plus_new;
        tempvar range_check_ptr = range_check_ptr;
    } else {
        assert refund_counter_after_current_auth = refund_counter;
        tempvar range_check_ptr = range_check_ptr;
    }

    local code_to_set_bytes: Bytes;
    // If auth.address is null (0x00..00), set empty code (clear delegation)
    if (auth.value.address.value == 0) {
        let (empty_data: felt*) = alloc();
        assert code_to_set_bytes = Bytes(new BytesStruct(data=empty_data, len=0));
        tempvar range_check_ptr = range_check_ptr;
    } else {
        // Otherwise, set the delegation indicator code
        let (buffer: felt*) = alloc();
        assert buffer[0] = EOA_DELEGATION_MARKER_BYTE_0;
        assert buffer[1] = EOA_DELEGATION_MARKER_BYTE_1;
        assert buffer[2] = EOA_DELEGATION_MARKER_BYTE_2;
        felt_to_bytes20_little(buffer + EOA_DELEGATION_MARKER_LEN, auth.value.address.value);
        assert code_to_set_bytes = Bytes(
            new BytesStruct(data=buffer, len=EOA_DELEGATED_CODE_LENGTH)
        );
        tempvar range_check_ptr = range_check_ptr;
    }

    set_code{state=state}(authority, code_to_set_bytes);
    increment_nonce{state=state}(authority);

    // Continue to the next authorization with the updated refund counter
    return _set_delegation_loop(
        authorizations, current_idx + 1, refund_counter_after_current_auth, block_env_chain_id
    );
}

// @notice Set the delegation code for the authorities in the message.
// @param message The transaction message.
// @return refund_counter The total gas refund accumulated from processing authorizations.
// @return err An EthereumException pointer if an error occurs (e.g., invalid block due to null code_address after processing), otherwise a null pointer.
func set_delegation{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    message: Message,
}() -> U256 {
    alloc_locals;
    tempvar initial_refund_counter = U256(new U256Struct(low=0, high=0));
    let chain_id = message.value.block_env.value.chain_id;
    let state = message.value.block_env.value.state;
    let accessed_addresses = message.value.accessed_addresses;
    let final_refund_counter = _set_delegation_loop{
        state=state, accessed_addresses=accessed_addresses
    }(message.value.tx_env.value.authorizations, 0, initial_refund_counter, chain_id);
    MessageImpl.set_accessed_addresses{message=message}(accessed_addresses);
    let block_env = message.value.block_env;
    BlockEnvImpl.set_state{block_env=block_env}(state);
    MessageImpl.set_block_env(block_env);

    if (cast(message.value.code_address.value, felt) == 0) {
        raise('InvalidBlock');
    }
    let current_msg_code_val = message.value.code;
    let is_delegated_final_check = is_valid_delegation(current_msg_code_val);
    if (is_delegated_final_check.value == TRUE) {
        MessageImpl.set_disable_precompiles{message=message}(bool(TRUE));
        let new_code_addr_opt = get_delegated_code_address(current_msg_code_val);
        MessageImpl.set_code_address{message=message}(new_code_addr_opt);
        tempvar new_code_addr = Address([new_code_addr_opt.value]);
        let msg_accessed_addresses = message.value.accessed_addresses;
        set_address_add{set_address=msg_accessed_addresses}(new_code_addr);
        MessageImpl.set_accessed_addresses{message=message}(msg_accessed_addresses);
        let state = message.value.block_env.value.state;
        let final_delegated_account = get_account{state=state}(new_code_addr);
        let final_delegated_code = get_account_code{state=state}(
            new_code_addr, final_delegated_account
        );
        BlockEnvImpl.set_state{block_env=block_env}(state);
        MessageImpl.set_block_env(block_env);
        MessageImpl.set_code{message=message}(final_delegated_code);
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    } else {
        tempvar message = message;
        tempvar range_check_ptr = range_check_ptr;
        tempvar bitwise_ptr = bitwise_ptr;
        tempvar keccak_ptr = keccak_ptr;
        tempvar poseidon_ptr = poseidon_ptr;
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    }

    return final_refund_counter;
}
