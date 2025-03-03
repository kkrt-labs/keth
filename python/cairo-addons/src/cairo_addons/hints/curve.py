from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def decompose_scalar_to_neg3_base(
    ids: VmConsts,
    memory: MemoryDict,
    ap: RelocatableValue,
    segments: MemorySegmentManager,
):
    from garaga.hints.neg_3 import neg_3_base_le

    assert 0 <= ids.scalar < 2**128
    digits = neg_3_base_le(ids.scalar)
    digits = digits + [0] * (82 - len(digits))
    # ruff: noqa: F821
    # ruff: noqa: F841
    segments.write_arg(ids.digits, digits)
    ids.d0 = digits[0]
    i = memory[ap] = 1  # Loop init


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

    is_on_curve = is_quad_residue(rhs, p)
    if is_on_curve == 1:
        square_root = sqrt_mod(rhs, p)
        if ids.v % 2 == square_root % 2:
            pass
        else:
            square_root = -square_root % p
    else:
        square_root = sqrt_mod(rhs * g, p)

    segments.load_data(ids.y_try.address_, int_to_uint384(square_root))
    segments.load_data(ids.is_on_curve.address_, int_to_uint384(is_on_curve))


@register_hint
def build_msm_hints_and_fill_memory(ids: VmConsts, memory: MemoryDict):
    """
    Builds Multi-Scalar Multiplication (MSM) hints and fills memory with SECP256K1 curve point data.

    This function:
    1. Constructs curve points and scalars for SECP256K1
    2. Serializes the data using MSMCalldataBuilder
    3. Processes the calldata into two parts: points and RLC sum components
    4. Fills the memory with the processed data
    """
    from garaga.definitions import BASE, N_LIMBS, CurveID, G1Point
    from garaga.hints.io import bigint_pack, fill_felt_ptr
    from garaga.starknet.tests_and_calldata_generators.msm import MSMCalldataBuilder

    # Initialize curve points and scalars
    curve_id = CurveID.SECP256K1
    r_point = (
        bigint_pack(ids.r_point.x, N_LIMBS, BASE),
        bigint_pack(ids.r_point.y, N_LIMBS, BASE),
    )
    points = [
        G1Point.get_nG(curve_id, 1),  # Generator point
        G1Point(r_point[0], r_point[1], curve_id),  # Signature point
    ]
    scalars = [ids.u1.low + 2**128 * ids.u1.high, ids.u2.low + 2**128 * ids.u2.high]

    # Generate and process calldata
    builder = MSMCalldataBuilder(curve_id, points, scalars)
    calldata = builder.serialize_to_calldata(
        include_digits_decomposition=False,
        include_points_and_scalars=False,
        serialize_as_pure_felt252_array=False,
        use_rust=True,
    )[1:]

    # Split calldata into points and remaining data
    points_offset = 3 * 2 * N_LIMBS  # 3 points × 2 coordinates × N_LIMBS
    Q_low_high_high_shifted = calldata[:points_offset]
    calldata_rest = calldata[points_offset:]

    # Process RLC sum dlog div components
    rlc_components = []
    for _ in range(4):
        array_len = calldata_rest.pop(0)
        array = calldata_rest[: array_len * N_LIMBS]
        rlc_components.extend(array)
        calldata_rest = calldata_rest[array_len * N_LIMBS :]

    # Verify RLC components length
    expected_len = (18 + 4 * 2) * N_LIMBS
    assert (
        len(rlc_components) == expected_len
    ), f"Invalid RLC components length: {len(rlc_components)}"

    # Fill memory with processed data
    rlc_coeff_u384_cast_offset = 4
    ecip_circuit_constants_offset = 20
    memory_offset = rlc_coeff_u384_cast_offset + ecip_circuit_constants_offset
    ecip_circuit_q_offset = 46 * N_LIMBS
    fill_felt_ptr(rlc_components, memory, ids.range_check96_ptr + memory_offset)
    fill_felt_ptr(
        Q_low_high_high_shifted,
        memory,
        ids.range_check96_ptr + memory_offset + ecip_circuit_q_offset,
    )


@register_hint
def ec_mul_msm_hints_and_fill_memory(ids: VmConsts, memory: MemoryDict):
    """
    Builds Multi-Scalar Multiplication (MSM) hints and fills memory with BN254 curve point data.

    This function:
    1. Constructs curve points and scalars for BN254
    2. Serializes the data using MSMCalldataBuilder
    3. Processes the calldata into two parts: points and RLC sum components
    4. Fills the memory with the processed data
    """
    from garaga.definitions import BASE, N_LIMBS, CurveID, G1Point
    from garaga.hints.io import bigint_pack, fill_felt_ptr
    from garaga.starknet.tests_and_calldata_generators.msm import MSMCalldataBuilder

    # Initialize curve points and scalars
    curve_id = CurveID.BN254
    p = (
        bigint_pack(ids.p.x, N_LIMBS, BASE),
        bigint_pack(ids.p.y, N_LIMBS, BASE),
    )
    point = [G1Point(p[0], p[1], curve_id)]
    scalar = [ids.scalar.low + 2**128 * ids.scalar.high]

    # Generate and process calldata
    builder = MSMCalldataBuilder(curve_id, point, scalar)
    calldata = builder.serialize_to_calldata(
        include_digits_decomposition=False,
        include_points_and_scalars=False,
        serialize_as_pure_felt252_array=False,
        use_rust=True,
    )[1:]

    # Split calldata into points and remaining data
    points_offset = 3 * 2 * N_LIMBS  # 3 points × 2 coordinates × N_LIMBS
    q_low_high_high_shifted = calldata[:points_offset]
    calldata_rest = calldata[points_offset:]

    # Process RLC sum dlog div components
    rlc_components = []
    for _ in range(4):
        array_len = calldata_rest.pop(0)
        array = calldata_rest[: array_len * N_LIMBS]
        rlc_components.extend(array)
        calldata_rest = calldata_rest[array_len * N_LIMBS :]

    # Verify RLC components length
    expected_len = (14 + 4 * 2) * N_LIMBS
    assert (
        len(rlc_components) == expected_len
    ), f"Invalid RLC components length: {len(rlc_components)}"

    # Fill memory with processed data
    rlc_coeff_u384_cast_offset = 3 * N_LIMBS
    ecip_circuit_constants_offset = 6 * N_LIMBS
    memory_offset = rlc_coeff_u384_cast_offset + ecip_circuit_constants_offset
    ecip_circuit_q_offset = 32 * N_LIMBS
    fill_felt_ptr(rlc_components, memory, ids.range_check96_ptr + memory_offset)
    fill_felt_ptr(
        q_low_high_high_shifted,
        memory,
        ids.range_check96_ptr + memory_offset + ecip_circuit_q_offset,
    )


@register_hint
def fill_add_mod_mul_mod_builtin_batch_one(
    ids: VmConsts, memory: MemoryDict, builtin_runners: dict
):
    from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner

    add_mod = None
    try:
        add_mod = (ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 1)
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
    except Exception:
        add_mod = None

    mul_mod = None
    try:
        mul_mod = (ids.mul_mod_ptr.address_, builtin_runners["mul_mod_builtin"], 1)
        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1
    except Exception:
        mul_mod = None

    ModBuiltinRunner.fill_memory(
        memory=memory,
        add_mod=add_mod,
        mul_mod=mul_mod,
    )


@register_hint
def fill_add_mod_mul_mod_builtin_batch_117_108(
    ids: VmConsts, memory: MemoryDict, builtin_runners: dict
):
    from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner

    assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
    assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

    ModBuiltinRunner.fill_memory(
        memory=memory,
        add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 117),
        mul_mod=(ids.mul_mod_ptr.address_, builtin_runners["mul_mod_builtin"], 108),
    )


@register_hint
def is_point_on_curve(ids: VmConsts):
    x = (
        ids.point.x.d0
        + ids.point.x.d1 * 2**96
        + ids.point.x.d2 * 2**192
        + ids.point.x.d3 * 2**288
    )
    y = (
        ids.point.y.d0
        + ids.point.y.d1 * 2**96
        + ids.point.y.d2 * 2**192
        + ids.point.y.d3 * 2**288
    )
    a = ids.a.d0 + ids.a.d1 * 2**96 + ids.a.d2 * 2**192 + ids.a.d3 * 2**288
    b = ids.b.d0 + ids.b.d1 * 2**96 + ids.b.d2 * 2**192 + ids.b.d3 * 2**288
    modulus = (
        ids.modulus.d0
        + ids.modulus.d1 * 2**96
        + ids.modulus.d2 * 2**192
        + ids.modulus.d3 * 2**288
    )

    rhs = (x**3 + a * x + b) % modulus
    lhs = y**2 % modulus
    is_on_curve = rhs == lhs
    ids.is_on_curve = is_on_curve
