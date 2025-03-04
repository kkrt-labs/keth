from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def has_six_uint384_remaining_hint(
    ids: VmConsts, memory: MemoryDict, ap: RelocatableValue
):
    memory[ap - 1] = ids.elements_end - ids.elements >= 6 * ids.N_LIMBS


@register_hint
def has_one_uint384_remaining_hint(
    ids: VmConsts, memory: MemoryDict, ap: RelocatableValue
):
    memory[ap - 1] = ids.elements_end - ids.elements >= ids.N_LIMBS


@register_hint
def felt_to_uint384_split_hint(ids: VmConsts):
    """
    Splits a felt into limbs for uint384 conversion.
    Ensures the highest limb (limbs[3]) is zero.
    """
    from garaga.hints.io import bigint_split

    limbs = bigint_split(ids.x, 4, 2**96)
    assert limbs[3] == 0
    ids.d0, ids.d1, ids.d2 = limbs[0], limbs[1], limbs[2]


@register_hint
def x_mod_p_eq_y_mod_p_hint(ids: VmConsts):
    """
    Packs x, y, and p values into bigints for uint384 operations.
    Returns 1 if x % p == y % p, 0 otherwise.
    """
    from garaga.hints.io import bigint_pack

    x = bigint_pack(ids.x, 4, 2**96)
    y = bigint_pack(ids.y, 4, 2**96)
    p = bigint_pack(ids.p, 4, 2**96)
    ids.x_mod_p_eq_y_mod_p = x % p == y % p


@register_hint
def x_is_neg_y_mod_p_hint(ids: VmConsts):
    """
    Packs x, y, and p values into bigints for uint384 operations.
    Returns 1 if x % p == -y % p, 0 otherwise.
    """
    from garaga.hints.io import bigint_pack

    x = bigint_pack(ids.x, 4, 2**96)
    y = bigint_pack(ids.y, 4, 2**96)
    p = bigint_pack(ids.p, 4, 2**96)
    ids.x_is_neg_y_mod_p = x % p == -y % p


@register_hint
def div_rem_hint(ids: VmConsts):
    """
    Computes the divider and remainder of x mod p.
    Returns (q, r) such that x = q * p + r
    """
    from garaga.hints.io import bigint_pack, bigint_split

    x = bigint_pack(ids.x, 4, 2**96)
    p = bigint_pack(ids.p, 4, 2**96)
    q, r = x.__divmod__(p)
    quo_limbs = bigint_split(q, 4, 2**96)
    rem_limbs = bigint_split(r, 4, 2**96)
    (
        ids.q.d0,
        ids.q.d1,
        ids.q.d2,
        ids.q.d3,
        ids.r.d0,
        ids.r.d1,
        ids.r.d2,
        ids.r.d3,
    ) = (
        quo_limbs[0],
        quo_limbs[1],
        quo_limbs[2],
        quo_limbs[3],
        rem_limbs[0],
        rem_limbs[1],
        rem_limbs[2],
        rem_limbs[3],
    )
