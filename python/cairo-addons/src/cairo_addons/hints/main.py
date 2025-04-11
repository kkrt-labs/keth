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
