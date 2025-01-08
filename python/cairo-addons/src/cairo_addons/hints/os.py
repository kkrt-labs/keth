from cairo_addons.hints.decorator import register_hint
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.vm_consts import VmConsts


@register_hint
def block(
    dict_manager: DictManager,
    segments: MemorySegmentManager,
    program_input: dict,
    ids: VmConsts,
):
    from tests.utils.hints import gen_arg_pydantic

    ids.block = gen_arg_pydantic(dict_manager, segments, program_input["block"])


@register_hint
def state(
    dict_manager: DictManager,
    segments: MemorySegmentManager,
    program_input: dict,
    ids: VmConsts,
):
    from tests.utils.hints import gen_arg_pydantic

    ids.state = gen_arg_pydantic(dict_manager, segments, program_input["state"])


@register_hint
def chain_id(ids: VmConsts):
    ids.chain_id = 1


@register_hint
def block_hashes(segments: MemorySegmentManager, ids: VmConsts):
    import random

    ids.block_hashes = segments.gen_arg(
        [random.randint(0, 2**128 - 1) for _ in range(256 * 2)]
    )
