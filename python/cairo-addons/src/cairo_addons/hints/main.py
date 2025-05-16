from typing import Callable

from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def main_inputs(ids: VmConsts, program_input: dict, gen_arg: Callable):
    from typing import Mapping, Optional, Union

    from ethereum.crypto.hash import Hash32
    from ethereum.prague.fork import Block, BlockChain
    from ethereum.prague.fork_types import Address
    from ethereum.prague.trie import InternalNode
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

    from ethereum.prague.fork import Block, BlockChain

    # Program inputs for STF function
    ids.chain = gen_arg(BlockChain, program_input["blockchain"])
    ids.block = gen_arg(Block, program_input["block"])


@register_hint
def teardown_inputs(ids: VmConsts, program_input: dict, gen_arg: Callable):
    from typing import Mapping, Optional, Tuple, Union

    from ethereum.crypto.hash import Hash32
    from ethereum.prague.blocks import Withdrawal
    from ethereum.prague.fork import Block, BlockChain
    from ethereum.prague.fork_types import Address
    from ethereum.prague.transactions import LegacyTransaction
    from ethereum.prague.trie import InternalNode, Trie
    from ethereum.prague.vm import BlockEnvironment, BlockOutput
    from ethereum_rlp import Extended
    from ethereum_types.bytes import Bytes, Bytes32

    # Program inputs for init.cairo
    ids.chain = gen_arg(BlockChain, program_input["blockchain"])
    ids.block = gen_arg(Block, program_input["block"])
    ids.init_withdrawals_trie = gen_arg(
        Trie[Bytes, Optional[Union[Bytes, Withdrawal]]],
        program_input["withdrawals_trie"],
    )

    #  Program inputs for body.cairo
    ids.block_transactions = gen_arg(
        Tuple[Union[LegacyTransaction, Bytes], ...],
        program_input["block_transactions"],
    )
    ids.block_env = gen_arg(BlockEnvironment, program_input["block_env"])
    ids.block_output = gen_arg(BlockOutput, program_input["block_output"])

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
    from typing import Tuple, Union

    from ethereum.prague.blocks import Header
    from ethereum.prague.transactions import LegacyTransaction
    from ethereum.prague.vm import BlockEnvironment, BlockOutput
    from ethereum_types.bytes import Bytes

    ids.block_header = gen_arg(Header, program_input["block_header"])
    ids.block_transactions = gen_arg(
        Tuple[Union[LegacyTransaction, Bytes], ...],
        program_input["block_transactions"],
    )
    ids.block_env = gen_arg(BlockEnvironment, program_input["block_env"])
    ids.block_output = gen_arg(BlockOutput, program_input["block_output"])
    ids.start_index = program_input["start_index"]
    ids.len = program_input["len"]


@register_hint
def aggregator_inputs(
    ids: VmConsts,
    program_input: dict,
    segments: MemorySegmentManager,
    memory: MemoryDict,
):
    # Python hint to load data from program_input
    # Assuming program_input is a dict as described in the design doc:

    # Extract data from the program_input hint variable
    keth_outputs_list = program_input["keth_segment_outputs"]
    keth_hashes = program_input["keth_segment_program_hashes"]
    num_body_chunks = program_input["n_body_chunks"]

    # Assign hints to Cairo local variables
    ids.n_body_chunks = num_body_chunks
    ids.init_program_hash = keth_hashes["init"]
    ids.body_program_hash = keth_hashes["body"]
    ids.teardown_program_hash = keth_hashes["teardown"]

    # Allocate memory for the serialized outputs and get pointers
    ids.serialized_init_output = segments.gen_arg(keth_outputs_list[0])

    # Allocate memory for the array of pointers to body outputs
    body_output_pointers = segments.add()
    # Allocate memory for each body output and store its pointer
    for i in range(num_body_chunks):
        body_output_ptr = segments.gen_arg(keth_outputs_list[i + 1])
        memory[body_output_pointers + i] = body_output_ptr
    ids.serialized_body_outputs = body_output_pointers

    ids.serialized_teardown_output = segments.gen_arg(
        keth_outputs_list[num_body_chunks + 1]
    )
