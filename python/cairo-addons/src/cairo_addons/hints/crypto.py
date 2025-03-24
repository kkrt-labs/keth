from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def bnf2_multiplicative_inverse(ids: VmConsts, segments: MemorySegmentManager):
    from ethereum.crypto.alt_bn128 import BNF2

    from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int

    b_c0 = uint384_to_int()(
        ids.b.value.c0.value.d0,
        ids.b.value.c0.value.d1,
        ids.b.value.c0.value.d2,
        ids.b.value.c0.value.d3,
    )
    b_c1 = uint384_to_int()(
        ids.b.value.c1.value.d0,
        ids.b.value.c1.value.d1,
        ids.b.value.c1.value.d2,
        ids.b.value.c1.value.d3,
    )
    b = BNF2([b_c0, b_c1])
    b_inv = b.multiplicative_inverse()
    bnf2_struct_ptr = segments.add(2)
    b_inv_c0_ptr = segments.gen_arg(int_to_uint384(b_inv[0]))
    b_inv_c1_ptr = segments.gen_arg(int_to_uint384(b_inv[1]))
    segments.load_data(bnf2_struct_ptr, [b_inv_c0_ptr, b_inv_c1_ptr])
    segments.load_data(ids.b_inv.address_, [bnf2_struct_ptr])
