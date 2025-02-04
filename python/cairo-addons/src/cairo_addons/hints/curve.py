from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def decompose_scalar_to_neg3_base(ids: VmConsts):
    from garaga.hints.neg_3 import neg_3_base_le

    assert 0 <= ids.scalar < 2**128
    digits = neg_3_base_le(ids.scalar)
    digits = digits + [0] * (82 - len(digits))
    # ruff: noqa: F821
    # ruff: noqa: F841
    i = 1  # Loop init


@register_hint
def set_ap_true_if_i_82(memory: MemoryDict, ap: RelocatableValue):
    # ruff: noqa: F821
    memory[ap] = 1 if i == 82 else 0


@register_hint
def digit_zero_hint(ids: VmConsts):
    # ruff: noqa: F821
    ids.d0 = digits[0]


@register_hint
def digit_i_hint(ids: VmConsts):
    # ruff: noqa: F821
    ids.di = digits[i - 1]


@register_hint
def increment_i_hint():
    # ruff: noqa: F821
    # ruff: noqa: F841
    i += 1


@register_hint
def compute_y_from_x_hint(ids: VmConsts, segments: MemorySegmentManager):
    """
    Compute y coordinate from x coordinate on elliptic curve y^2 = x^3 + ax + b.
    If point is not on curve, computes y for point (g*h, y) instead.
    """
    from starkware.python.math_utils import is_quad_residue
    from sympy import sqrt_mod

    from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int

    a = uint384_to_int(ids.a.d0, ids.a.d1, ids.a.d2, ids.a.d3)
    b = uint384_to_int(ids.b.d0, ids.b.d1, ids.b.d2, ids.b.d3)
    p = uint384_to_int(ids.p.d0, ids.p.d1, ids.p.d2, ids.p.d3)
    g = uint384_to_int(ids.g.d0, ids.g.d1, ids.g.d2, ids.g.d3)
    x = uint384_to_int(ids.x.d0, ids.x.d1, ids.x.d2, ids.x.d3)
    rhs = (x**3 + a * x + b) % p

    ids.is_on_curve = is_quad_residue(rhs, p)
    if ids.is_on_curve == 1:
        square_root = sqrt_mod(rhs, p)
        if ids.v % 2 == square_root % 2:
            pass
        else:
            square_root = -square_root % p
    else:
        square_root = sqrt_mod(rhs * g, p)

    segments.load_data(ids.y_try.address_, int_to_uint384(square_root))


@register_hint
def build_msm_hints_and_fill_memory(ids: VmConsts, memory: MemoryDict):
    """
    Builds MSM hints and fills memory with curve point data for SECP256K1.
    """
    from garaga.definitions import CurveID, G1Point
    from garaga.hints.io import bigint_pack, bigint_split
    from garaga.starknet.tests_and_calldata_generators.msm import MSMCalldataBuilder

    curve_id = CurveID.SECP256K1
    r_point = (
        bigint_pack(ids.r_point.x, 4, 2**96),
        bigint_pack(ids.r_point.y, 4, 2**96),
    )
    points = [G1Point.get_nG(curve_id, 1), G1Point(r_point[0], r_point[1], curve_id)]
    scalars = [ids.u1.low + 2**128 * ids.u1.high, ids.u2.low + 2**128 * ids.u2.high]
    builder = MSMCalldataBuilder(curve_id, points, scalars)
    (msm_hint, derive_point_from_x_hint) = builder.build_msm_hints()
    Q_low, Q_high, Q_high_shifted, RLCSumDlogDiv = msm_hint.elmts

    def fill_elmt_at_index(
        x, ptr: object, memory: object, index: int, static_offset: int = 0
    ):
        limbs = bigint_split(x, 4, 2**96)
        for i in range(4):
            memory[ptr + index * 4 + i + static_offset] = limbs[i]

    def fill_elmts_at_index(
        x,
        ptr: object,
        memory: object,
        index: int,
        static_offset: int = 0,
    ):
        for i in range(len(x)):
            fill_elmt_at_index(x[i], ptr + i * 4, memory, index, static_offset)

    rlc_sum_dlog_div_coeffs = (
        RLCSumDlogDiv.a_num
        + RLCSumDlogDiv.a_den
        + RLCSumDlogDiv.b_num
        + RLCSumDlogDiv.b_den
    )
    assert (
        len(rlc_sum_dlog_div_coeffs) == 18 + 4 * 2
    ), f"len(rlc_sum_dlog_div_coeffs) == {len(rlc_sum_dlog_div_coeffs)} != {18 + 4*2}"

    offset = 4
    fill_elmts_at_index(
        rlc_sum_dlog_div_coeffs, ids.range_check96_ptr, memory, 4, offset
    )

    fill_elmt_at_index(Q_low[0], ids.range_check96_ptr, memory, 50, offset)
    fill_elmt_at_index(Q_low[1], ids.range_check96_ptr, memory, 51, offset)
    fill_elmt_at_index(Q_high[0], ids.range_check96_ptr, memory, 52, offset)
    fill_elmt_at_index(Q_high[1], ids.range_check96_ptr, memory, 53, offset)
    fill_elmt_at_index(Q_high_shifted[0], ids.range_check96_ptr, memory, 54, offset)
    fill_elmt_at_index(Q_high_shifted[1], ids.range_check96_ptr, memory, 55, offset)
