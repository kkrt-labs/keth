from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def felt252_to_bytes(ids: VmConsts, memory: MemoryDict):
    from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME

    current_value = ids.value
    for i in range(0, ids.len):
        memory[ids.output + i] = res_i = (int(current_value) % DEFAULT_PRIME) % ids.base
        assert res_i < ids.bound, f"felt_to_bytes: Limb {res_i} is out of range."
        current_value = current_value // ids.base
