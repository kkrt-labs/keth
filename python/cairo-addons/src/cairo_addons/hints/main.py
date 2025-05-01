from typing import Callable

from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def main_inputs(ids: VmConsts, program_input: dict, gen_arg: Callable):
    from typing import Mapping, Optional, Union

    from ethereum.cancun.fork import Block, BlockChain
    from ethereum.cancun.fork_types import Address
    from ethereum.cancun.trie import InternalNode
    from ethereum.crypto.hash import Hash32
    from ethereum_rlp import Extended
    from ethereum_types.bytes import Bytes, Bytes32

    # Program inputs for STF function
    ids.chain = gen_arg(BlockChain, program_input["blockchain"])
    ids.block = gen_arg(Block, program_input["block"])

    # Program inputs for Trie diffs
    ids.node_store = gen_arg(Mapping[Hash32, Bytes], program_input["node_store"])
    ids.address_preimages = gen_arg(
        Mapping[Hash32, Address], program_input["address_preimages"]
    )
    ids.storage_key_preimages = gen_arg(
        Mapping[Hash32, Bytes32], program_input["storage_key_preimages"]
    )
    ids.post_state_root = gen_arg(
        Optional[Union[InternalNode, Extended]], program_input["post_state_root"]
    )


@register_hint
def init_inputs(ids: VmConsts, program_input: dict, gen_arg: Callable):

    from ethereum.cancun.fork import Block, BlockChain

    # Program inputs for STF function
    ids.chain = gen_arg(BlockChain, program_input["blockchain"])
    ids.block = gen_arg(Block, program_input["block"])


@register_hint
def teardown_inputs(ids: VmConsts, program_input: dict, gen_arg: Callable):
    from typing import List, Mapping, Optional, Tuple, Union

    from ethereum.cancun.blocks import Log, Receipt, Withdrawal
    from ethereum.cancun.fork import Block, BlockChain
    from ethereum.cancun.fork_types import Address
    from ethereum.cancun.state import State
    from ethereum.cancun.transactions import LegacyTransaction
    from ethereum.cancun.trie import InternalNode, Trie
    from ethereum.crypto.hash import Hash32
    from ethereum_rlp import Extended
    from ethereum_types.bytes import Bytes, Bytes32
    from ethereum_types.numeric import U64, Uint

    # Program inputs for init.cairo
    ids.chain = gen_arg(BlockChain, program_input["blockchain"])
    ids.block = gen_arg(Block, program_input["block"])
    ids.withdrawals_trie = gen_arg(
        Trie[Bytes, Optional[Union[Bytes, Withdrawal]]],
        program_input["withdrawals_trie"],
    )

    #  Program inputs for body.cairo
    ids.block_transactions = gen_arg(
        Tuple[Union[LegacyTransaction, Bytes], ...],
        program_input["block_transactions"],
    )
    ids.state = gen_arg(State, program_input["state"])
    ids.transactions_trie = gen_arg(
        Trie[Bytes, Optional[Union[Bytes, LegacyTransaction]]],
        program_input["transactions_trie"],
    )
    ids.receipts_trie = gen_arg(
        Trie[Bytes, Optional[Union[Bytes, Receipt]]], program_input["receipts_trie"]
    )
    ids.block_logs = gen_arg(Tuple[Log, ...], program_input["block_logs"])
    ids.block_hashes = gen_arg(List[Hash32], program_input["block_hashes"])
    ids.gas_available = gen_arg(Uint, program_input["gas_available"])
    ids.chain_id = gen_arg(U64, program_input["chain_id"])
    ids.blob_gas_used = gen_arg(Uint, program_input["blob_gas_used"])
    ids.excess_blob_gas = gen_arg(U64, program_input["excess_blob_gas"])

    # Program inputs for Trie diffs
    ids.node_store = gen_arg(Mapping[Hash32, Bytes], program_input["node_store"])
    ids.address_preimages = gen_arg(
        Mapping[Hash32, Address], program_input["address_preimages"]
    )
    ids.storage_key_preimages = gen_arg(
        Mapping[Hash32, Bytes32], program_input["storage_key_preimages"]
    )
    ids.post_state_root = gen_arg(
        Optional[Union[InternalNode, Extended]], program_input["post_state_root"]
    )


@register_hint
def body_inputs(ids: VmConsts, program_input: dict, gen_arg: Callable):
    from typing import List, Optional, Tuple, Union

    from ethereum.cancun.blocks import Header, Log, Receipt
    from ethereum.cancun.state import State
    from ethereum.cancun.transactions import LegacyTransaction
    from ethereum.cancun.trie import Trie
    from ethereum.crypto.hash import Hash32
    from ethereum_types.bytes import Bytes
    from ethereum_types.numeric import U64, Uint

    ids.block_header = gen_arg(Header, program_input["block_header"])
    ids.block_transactions = gen_arg(
        Tuple[Union[LegacyTransaction, Bytes], ...],
        program_input["block_transactions"],
    )
    ids.state = gen_arg(State, program_input["state"])
    ids.transactions_trie = gen_arg(
        Trie[Bytes, Optional[Union[Bytes, LegacyTransaction]]],
        program_input["transactions_trie"],
    )
    ids.receipts_trie = gen_arg(
        Trie[Bytes, Optional[Union[Bytes, Receipt]]], program_input["receipts_trie"]
    )
    ids.block_logs = gen_arg(Tuple[Log, ...], program_input["block_logs"])
    ids.block_hashes = gen_arg(List[Hash32], program_input["block_hashes"])
    ids.gas_available = gen_arg(Uint, program_input["gas_available"])
    ids.chain_id = gen_arg(U64, program_input["chain_id"])
    ids.blob_gas_used = gen_arg(Uint, program_input["blob_gas_used"])
    ids.excess_blob_gas = gen_arg(U64, program_input["excess_blob_gas"])
    ids.start_index = program_input["start_index"]
    ids.len = program_input["len"]
