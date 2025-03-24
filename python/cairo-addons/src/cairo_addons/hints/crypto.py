from ethereum.crypto.alt_bn128 import BNF2
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def bnf2_multiplicative_inverse(ids: VmConsts):
    a_c0 = (
        ids.a.value.c0.value.d0
        + ids.a.value.c0.value.d1 * 2**96
        + ids.a.value.c0.value.d2 * 2**192
        + ids.a.value.c0.value.d3 * 2**288
    )
    a_c1 = (
        ids.a.value.c1.value.d0
        + ids.a.value.c1.value.d1 * 2**96
        + ids.a.value.c1.value.d2 * 2**192
        + ids.a.value.c1.value.d3 * 2**288
    )
    a = BNF2(a_c0, a_c1)
    _a_inv = a.multiplicative_inverse()
