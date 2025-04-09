from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def bnf_multiplicative_inverse(ids: VmConsts, segments: MemorySegmentManager):
    from ethereum.crypto.alt_bn128 import BNF

    from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int

    # Extract the value from the BNF element
    b_val = uint384_to_int(
        ids.b.value.c0.value.d0,
        ids.b.value.c0.value.d1,
        ids.b.value.c0.value.d2,
        ids.b.value.c0.value.d3,
    )

    # Create a BNF element and calculate its inverse
    b = BNF(b_val)
    b_inv = b.multiplicative_inverse()

    # Store the result in the b_inv variable
    bnf_struct_ptr = segments.add()
    b_inv_ptr = segments.gen_arg(int_to_uint384(int(b_inv)))
    segments.load_data(bnf_struct_ptr, [b_inv_ptr])
    segments.load_data(ids.b_inv.address_, [bnf_struct_ptr])


@register_hint
def bnf2_multiplicative_inverse(ids: VmConsts, segments: MemorySegmentManager):
    from ethereum.crypto.alt_bn128 import BNF2

    from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int

    b_c0 = uint384_to_int(
        ids.b.value.c0.value.d0,
        ids.b.value.c0.value.d1,
        ids.b.value.c0.value.d2,
        ids.b.value.c0.value.d3,
    )
    b_c1 = uint384_to_int(
        ids.b.value.c1.value.d0,
        ids.b.value.c1.value.d1,
        ids.b.value.c1.value.d2,
        ids.b.value.c1.value.d3,
    )
    b = BNF2([b_c0, b_c1])
    b_inv = b.multiplicative_inverse()
    bnf2_struct_ptr = segments.add()
    b_inv_c0_ptr = segments.gen_arg(int_to_uint384(b_inv[0]))
    b_inv_c1_ptr = segments.gen_arg(int_to_uint384(b_inv[1]))
    segments.load_data(bnf2_struct_ptr, [b_inv_c0_ptr, b_inv_c1_ptr])
    segments.load_data(ids.b_inv.address_, [bnf2_struct_ptr])


@register_hint
def bnf12_multiplicative_inverse(ids: VmConsts, segments: MemorySegmentManager):
    from ethereum.crypto.alt_bn128 import BNF12

    from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int

    bnf12_coeffs = []
    for i in range(12):
        coeff_attr = f"c{i}"
        coeff = getattr(ids.b.value, coeff_attr)
        bnf12_coeffs.append(
            uint384_to_int(
                coeff.value.d0,
                coeff.value.d1,
                coeff.value.d2,
                coeff.value.d3,
            )
        )
    b = BNF12(bnf12_coeffs)
    b_inv = b.multiplicative_inverse()
    bnf12_struct_ptr = segments.add()
    b_inv_coeffs_ptr = [segments.gen_arg(int_to_uint384(b_inv[i])) for i in range(12)]
    segments.load_data(bnf12_struct_ptr, b_inv_coeffs_ptr)
    segments.load_data(ids.b_inv.address_, [bnf12_struct_ptr])


@register_hint
def blsf_multiplicative_inverse(ids: VmConsts, segments: MemorySegmentManager):
    from py_ecc.fields import optimized_bls12_381_FQ as BLSF

    from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int

    # Extract the value from the BNF element
    b_val = uint384_to_int(
        ids.b.value.c0.value.d0,
        ids.b.value.c0.value.d1,
        ids.b.value.c0.value.d2,
        ids.b.value.c0.value.d3,
    )

    # Create a BLSF element and calculate its inverse
    b = BLSF(b_val)
    b_inv = 1 / b

    # Store the result in the b_inv variable
    blsf_struct_ptr = segments.add()
    b_inv_ptr = segments.gen_arg(int_to_uint384(int(b_inv)))
    segments.load_data(blsf_struct_ptr, [b_inv_ptr])
    segments.load_data(ids.b_inv.address_, [blsf_struct_ptr])


@register_hint
def blsf2_multiplicative_inverse(ids: VmConsts, segments: MemorySegmentManager):
    from py_ecc.fields import optimized_bls12_381_FQ2 as BLSF2

    from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int

    b_c0 = uint384_to_int(
        ids.b.value.c0.value.d0,
        ids.b.value.c0.value.d1,
        ids.b.value.c0.value.d2,
        ids.b.value.c0.value.d3,
    )
    b_c1 = uint384_to_int(
        ids.b.value.c1.value.d0,
        ids.b.value.c1.value.d1,
        ids.b.value.c1.value.d2,
        ids.b.value.c1.value.d3,
    )
    b = BLSF2([b_c0, b_c1])
    b_inv = 1 / b

    blsf2_struct_ptr = segments.add()
    b_inv_c0_ptr = segments.gen_arg(int_to_uint384(b_inv[0]))
    b_inv_c1_ptr = segments.gen_arg(int_to_uint384(b_inv[1]))
    segments.load_data(blsf2_struct_ptr, [b_inv_c0_ptr, b_inv_c1_ptr])
    segments.load_data(ids.b_inv.address_, [blsf2_struct_ptr])


@register_hint
def decompress_G1_hint(ids: VmConsts, segments: MemorySegmentManager):
    from py_ecc.bls.point_compression import decompress_G1
    from py_ecc.bls.typing import G1Compressed
    from py_ecc.fields import optimized_bls12_381_FQ as FQ
    from py_ecc.optimized_bls12_381.optimized_curve import (
        b,
        is_on_curve,
        normalize,
    )

    from cairo_addons.utils.uint384 import int_to_uint384, uint384_to_int

    z_int = uint384_to_int(
        ids.z.value.d0,
        ids.z.value.d1,
        ids.z.value.d2,
        ids.z.value.d3,
    )
    try:
        point = normalize(decompress_G1(G1Compressed(z_int)))
    except ValueError:
        # return a point that is not on the curve
        point = (FQ.zero(), FQ.one(), FQ.one())
        assert not is_on_curve(point, b)
    y_ptr = segments.gen_arg(int_to_uint384(int(point[1])))
    blsf_y_struct_ptr = segments.add()
    segments.load_data(blsf_y_struct_ptr, [y_ptr])
    segments.load_data(ids.y_blsf.address_, [blsf_y_struct_ptr])
