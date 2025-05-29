"""
Test suite for EIP-7702 EOA delegation implementation in Cairo.

This module tests the Cairo implementation of EIP-7702 (Set EOA account code)
against the Python reference implementation using hypothesis for differential testing.
"""

from ethereum.crypto.elliptic_curve import SECP256K1N
from ethereum.crypto.hash import keccak256
from ethereum.prague.fork_types import Account, Address, Authorization
from ethereum.prague.state import set_account
from ethereum.prague.vm import Message, TransactionEnvironment
from ethereum.prague.vm.eoa_delegation import (
    access_delegation,
    get_delegated_code_address,
    is_valid_delegation,
    recover_authority,
    set_delegation,
)
from ethereum.utils.hexadecimal import hex_to_hash
from ethereum_types.bytes import Bytes
from ethereum_types.numeric import U8, U64, U256, Uint
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder
from tests.utils.strategies import private_key

# Constants from EIP-7702 specification
EOA_DELEGATION_MARKER = bytes([0xEF, 0x01, 0x00])
EOA_DELEGATED_CODE_LENGTH = 23  # 3 marker + 20 address


# Hypothesis strategies for generating test data
@st.composite
def bytes_strategy(draw):
    """Generate Bytes objects for testing."""
    # Generate various lengths of byte arrays
    length = draw(
        st.one_of(
            st.just(0),  # Empty
            st.just(EOA_DELEGATED_CODE_LENGTH),  # Correct length
            st.integers(min_value=1, max_value=100),  # Various other lengths
        )
    )

    if length == EOA_DELEGATED_CODE_LENGTH:
        # Sometimes generate valid delegation codes
        if draw(st.booleans()):
            # Valid delegation code
            address_bytes = draw(st.binary(min_size=20, max_size=20))
            data = EOA_DELEGATION_MARKER + address_bytes
        else:
            # Invalid delegation code with correct length
            data = draw(st.binary(min_size=length, max_size=length))
    else:
        # Random bytes of various lengths
        data = draw(st.binary(min_size=length, max_size=length))

    return Bytes(data)


@st.composite
def valid_delegation_code_strategy(draw):
    """Generate valid delegation codes with random addresses."""
    address_bytes = draw(st.binary(min_size=20, max_size=20))
    data = EOA_DELEGATION_MARKER + address_bytes
    return Bytes(data)


@st.composite
def message_with_authorizations_strategy(draw):
    # Generate authorizations (0 to 3 for reasonable test size)
    num_authorizations = draw(st.integers(min_value=0, max_value=3))
    authorizations = tuple(
        draw(authorization_strategy()) for _ in range(num_authorizations)
    )

    # Create a message with proper setup
    message = draw(
        MessageBuilder()
        .with_block_env()
        .with_current_target()
        .with_code_address(st.from_type(Address))  # Ensure code_address is not None
        .with_code(bytes_strategy())  # May or may not be delegation code
        .build()
    )

    # Create a new transaction environment with our authorizations
    # Note: We copy all fields from the original tx_env except authorizations
    tx_env = TransactionEnvironment(
        origin=message.tx_env.origin,
        gas_price=message.tx_env.gas_price,
        gas=message.tx_env.gas,
        access_list_addresses=message.tx_env.access_list_addresses,
        access_list_storage_keys=message.tx_env.access_list_storage_keys,
        transient_storage=message.tx_env.transient_storage,
        blob_versioned_hashes=message.tx_env.blob_versioned_hashes,
        authorizations=authorizations,
        index_in_block=message.tx_env.index_in_block,
        tx_hash=message.tx_env.tx_hash,
    )

    # Create new message with the updated tx_env

    message_with_auths = Message(
        block_env=message.block_env,
        tx_env=tx_env,
        caller=message.caller,
        target=message.target,
        current_target=message.current_target,
        gas=message.gas,
        value=message.value,
        data=message.data,
        code_address=message.code_address,
        code=message.code,
        depth=message.depth,
        should_transfer_value=message.should_transfer_value,
        is_static=message.is_static,
        accessed_addresses=message.accessed_addresses,
        accessed_storage_keys=message.accessed_storage_keys,
        disable_precompiles=message.disable_precompiles,
        parent_evm=message.parent_evm,
    )

    # Set up authority accounts in state for valid authorizations
    for auth in authorizations:
        try:
            # Try to recover the authority to set up the account
            authority = recover_authority(auth)

            # Create an account for this authority with matching nonce
            authority_account = Account(
                nonce=Uint(auth.nonce),
                balance=U256(0),
                code_hash=keccak256(Bytes(b"")),  # Empty code
                storage_root=hex_to_hash(
                    "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                ),
                code=Bytes(b""),
            )
            set_account(
                message_with_auths.block_env.state, authority, authority_account
            )

            # If auth.address is not null, set up the target account too
            if auth.address != Address(b"\x00" * 20):
                target_account = Account(
                    nonce=Uint(0),
                    balance=U256(0),
                    code_hash=keccak256(Bytes(b"")),
                    storage_root=hex_to_hash(
                        "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
                    ),
                    code=Bytes(b""),
                )
                set_account(
                    message_with_auths.block_env.state, auth.address, target_account
                )
        except Exception:
            # If authority recovery fails, skip setting up the account
            # This will test the error handling path
            pass

    return message_with_auths


@st.composite
def evm_with_delegation_strategy(draw):
    """Generate EVM objects with accounts that may have delegation codes."""
    # Create an EVM with proper state setup
    evm = draw(
        EvmBuilder()
        .with_gas_left()
        .with_accessed_addresses()
        .with_message(
            MessageBuilder()
            .with_block_env()
            .with_tx_env()
            .with_current_target()
            .build()
        )
        .build()
    )

    # Generate an address to test
    test_address = draw(st.from_type(Address))

    # Generate code for the account (may or may not be delegation code)
    code_type = draw(
        st.sampled_from(
            ["empty", "invalid_delegation", "valid_delegation", "regular_code"]
        )
    )

    if code_type == "empty":
        account_code = Bytes(b"")
    elif code_type == "invalid_delegation":
        # Generate invalid delegation codes
        invalid_type = draw(
            st.sampled_from(["wrong_length", "wrong_marker", "partial_marker"])
        )
        if invalid_type == "wrong_length":
            account_code = draw(
                bytes_strategy().filter(lambda x: len(x) != EOA_DELEGATED_CODE_LENGTH)
            )
        elif invalid_type == "wrong_marker":
            # Correct length but wrong marker
            wrong_data = draw(
                st.binary(
                    min_size=EOA_DELEGATED_CODE_LENGTH,
                    max_size=EOA_DELEGATED_CODE_LENGTH,
                )
            )
            # Ensure it doesn't accidentally have the right marker
            if wrong_data[:3] == EOA_DELEGATION_MARKER:
                wrong_data = b"\x00\x01\x00" + wrong_data[3:]
            account_code = Bytes(wrong_data)
        else:  # partial_marker
            account_code = Bytes(
                EOA_DELEGATION_MARKER[:2] + b"\x00" * 21
            )  # Wrong third byte
    elif code_type == "valid_delegation":
        # Generate valid delegation code
        delegated_address = draw(st.from_type(Address))
        account_code = Bytes(EOA_DELEGATION_MARKER + delegated_address)

        # For valid delegation, also set up the delegated account to avoid exceptions
        delegated_code_hash = keccak256(Bytes(b""))  # Empty code for delegated account
        empty_storage_root = hex_to_hash(
            "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
        )
        delegated_account = Account(
            nonce=Uint(0),
            balance=U256(0),
            code_hash=delegated_code_hash,
            storage_root=empty_storage_root,
            code=Bytes(b""),
        )
        set_account(evm.message.block_env.state, delegated_address, delegated_account)
    else:  # regular_code
        # Generate regular contract code
        account_code = draw(st.binary(min_size=1, max_size=100).map(Bytes))

    # Calculate code hash and use empty storage root
    code_hash = keccak256(account_code)
    empty_storage_root = hex_to_hash(
        "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421"
    )

    account = Account(
        nonce=Uint(0),
        balance=U256(0),
        code_hash=code_hash,
        storage_root=empty_storage_root,
        code=account_code,
    )
    set_account(evm.message.block_env.state, test_address, account)

    return evm, test_address


@st.composite
def authorization_strategy(draw):
    """Generate Authorization objects for testing, inspired by ecrecover_data."""
    # Generate a private key for creating real signatures
    pkey = draw(private_key)

    # Generate authorization data
    chain_id = draw(st.integers(min_value=0, max_value=2**64 - 1))
    address_bytes = draw(st.binary(min_size=20, max_size=20))
    nonce = draw(st.integers(min_value=0, max_value=2**64 - 1))

    # Create the message that would be signed for EIP-7702
    # This follows the same pattern as the Python implementation:
    # SET_CODE_TX_MAGIC + rlp.encode((chain_id, address, nonce))
    from ethereum_rlp import rlp

    message_data = b"\x05" + rlp.encode(
        (U256(chain_id), Address(address_bytes), U64(nonce))
    )

    # Hash the message
    from ethereum.crypto.hash import keccak256

    message_hash = keccak256(message_data)

    # Choose test case type
    test_case = draw(
        st.sampled_from(
            [
                "valid_signature",  # Normal valid case
                "invalid_r_overflow",  # r >= SECP256K1N
                "invalid_r_zero",  # r = 0
                "invalid_s_overflow",  # s >= SECP256K1N
                "invalid_s_zero",  # s = 0
                "invalid_s_high",  # s > SECP256K1N // 2
                "invalid_y_parity",  # y_parity not 0 or 1
            ]
        )
    )

    if test_case == "valid_signature":
        # Create a real signature
        signature = pkey.sign_msg_hash(message_hash)
        r = U256(signature.r)
        s = U256(signature.s)
        y_parity = U8(signature.v)
    else:
        # Create invalid signatures for testing error cases
        signature = pkey.sign_msg_hash(message_hash)
        r = U256(signature.r)
        s = U256(signature.s)
        y_parity = U8(signature.v)

        if test_case == "invalid_r_overflow":
            r = U256(int(SECP256K1N) + 1)
        elif test_case == "invalid_r_zero":
            r = U256(0)
        elif test_case == "invalid_s_overflow":
            s = U256(int(SECP256K1N) + 1)
        elif test_case == "invalid_s_zero":
            s = U256(0)
        elif test_case == "invalid_s_high":
            s = U256(int(SECP256K1N) // 2 + 1)
        elif test_case == "invalid_y_parity":
            y_parity = U8(draw(st.integers(min_value=2, max_value=255)))

    return Authorization(
        chain_id=U256(chain_id),
        address=Address(address_bytes),
        nonce=Uint(nonce),
        y_parity=y_parity,
        r=r,
        s=s,
    )


class TestEOADelegation:
    @given(code=bytes_strategy())
    def test_is_valid_delegation(self, cairo_run, code: Bytes):
        try:
            cairo_result = cairo_run("is_valid_delegation", code)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                is_valid_delegation(code)
            return

        assert bool(cairo_result) == is_valid_delegation(code)

    @given(code=bytes_strategy())
    def test_get_delegated_code_address(self, cairo_run, code: Bytes):
        try:
            cairo_result = cairo_run("get_delegated_code_address", code)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                get_delegated_code_address(code)
            return

        python_result = get_delegated_code_address(code)

        assert cairo_result == python_result

    @given(code=valid_delegation_code_strategy())
    def test_valid_delegation_codes(self, cairo_run, code: Bytes):
        try:
            cairo_valid = cairo_run("is_valid_delegation", code)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                is_valid_delegation(code)
            return

        python_valid = is_valid_delegation(code)
        assert bool(cairo_valid) == python_valid
        assert python_valid  # Should always be true for valid codes

    @given(authorization=authorization_strategy())
    def test_recover_authority(self, cairo_run, authorization: Authorization):
        try:
            cairo_result = cairo_run("recover_authority", authorization)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                recover_authority(authorization)
            return

        assert cairo_result == recover_authority(authorization)

    @given(evm_and_address=evm_with_delegation_strategy())
    def test_access_delegation(self, cairo_run, evm_and_address):
        evm, address = evm_and_address

        try:
            cairo_evm, cairo_result = cairo_run("access_delegation", evm, address)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                access_delegation(evm, address)
            return

        python_result = access_delegation(evm, address)

        assert cairo_evm == evm
        assert tuple(cairo_result) == python_result

    @given(message=message_with_authorizations_strategy())
    def test_set_delegation(self, cairo_run, message):
        try:
            cairo_message, cairo_result = cairo_run("set_delegation", message)
        except Exception as cairo_error:
            with strict_raises(type(cairo_error)):
                set_delegation(message)
            return

        python_result = set_delegation(message)
        assert cairo_result == python_result
        assert cairo_message == message
