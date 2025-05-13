from typing import Tuple

from ethereum.cancun.fork_types import Account, Address
from ethereum.cancun.state import set_account
from ethereum.cancun.transactions import Transaction
from ethereum.cancun.trie import root
from ethereum.cancun.utils.message import prepare_message
from ethereum.cancun.vm import BlockEnvironment, TransactionEnvironment
from ethereum.crypto.hash import keccak256
from ethereum_types.bytes import Bytes, Bytes0
from ethereum_types.numeric import U256, Uint
from hypothesis import given
from hypothesis import strategies as st

from mpt.ethereum_tries import EMPTY_TRIE_HASH


@st.composite
def block_env_tx_env_and_tx(draw):
    block_env: BlockEnvironment = draw(st.from_type(BlockEnvironment))
    tx_env: TransactionEnvironment = draw(st.from_type(TransactionEnvironment))
    tx: Transaction = draw(st.from_type(Transaction))

    # Ensure origin account exists with a nonce for contract creation if 'to' is Bytes0
    if isinstance(tx.to, Bytes0):
        origin_address = tx_env.origin
        # Ensure nonce is at least 1 for contract creation based on current nonce
        nonce = draw(st.integers(min_value=1, max_value=2**64 - 1).map(Uint))
        if origin_address in block_env.state._storage_tries:
            storage_root = root(block_env.state._storage_tries[origin_address])
        else:
            storage_root = EMPTY_TRIE_HASH

        account_code = draw(st.from_type(Bytes))
        account_code_hash = keccak256(account_code)
        account = Account(
            nonce=nonce,
            balance=draw(st.from_type(U256)),
            code=account_code,
            code_hash=account_code_hash,
            storage_root=storage_root,
        )
        set_account(block_env.state, origin_address, account)

    # Ensure target account exists if 'to' is an address for message call
    if isinstance(tx.to, Address):
        target_address = tx.to
        if not block_env.state._main_trie._data.get(target_address):
            # Add a default account if it doesn't exist
            if target_address in block_env.state._storage_tries:
                storage_root = root(block_env.state._storage_tries[target_address])
            else:
                storage_root = EMPTY_TRIE_HASH
            account_code = draw(st.from_type(Bytes))
            account_code_hash = keccak256(account_code)
            account = Account(
                nonce=draw(st.from_type(Uint)),
                balance=draw(st.from_type(U256)),
                code=account_code,
                code_hash=account_code_hash,
                storage_root=storage_root,
            )
            set_account(block_env.state, target_address, account)

    return block_env, tx_env, tx


class TestMessage:
    @given(
        env_data=block_env_tx_env_and_tx(),
    )
    def test_prepare_message(
        self,
        cairo_run,
        env_data: Tuple[BlockEnvironment, TransactionEnvironment, Transaction],
    ):
        block_env, tx_env, tx = env_data
        cairo_block_env, cairo_tx_env, cairo_message = cairo_run(
            "prepare_message",
            block_env,
            tx_env,
            tx,
        )
        evm_message = prepare_message(
            block_env,
            tx_env,
            tx,
        )
        assert cairo_message == evm_message
        assert cairo_block_env == block_env
        assert cairo_tx_env == tx_env
