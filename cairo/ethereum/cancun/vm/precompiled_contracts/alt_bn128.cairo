from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    ModBuiltin,
    PoseidonBuiltin,
    UInt384,
)
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memset import memset
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import OutOfGasError
from ethereum.utils.numeric import U256_from_be_bytes, U256_le, divmod
from ethereum.cancun.vm.gas import charge_gas
from cairo_core.numeric import U256, U256Struct, U384, Uint
from ethereum_types.bytes import Bytes, BytesStruct
from ethereum.cancun.vm.memory import buffer_read
from cairo_ec.curve.alt_bn128 import alt_bn128
from cairo_ec.ec_ops import ec_add, ec_mul
from cairo_ec.curve.g1_point import G1Point, G1PointStruct, G1Point__eq__, G1Point_zero
from cairo_ec.circuits.ec_ops_compiled import assert_not_on_curve, assert_on_curve
from cairo_ec.uint384 import uint256_to_uint384
from cairo_core.maths import felt252_to_bytes_be
from starkware.cairo.common.registers import get_fp_and_pc
from ethereum.crypto.alt_bn128 import (
    BNF,
    BNFStruct,
    BNF2,
    BNF2Struct,
    BNF12,
    BNF12_ONE,
    BNP__eq__,
    BNP2__eq__,
    BNF12__eq__,
    bnp_init,
    bnp2_init,
    bnp_mul_by,
    bnp2_mul_by,
    bnf12_mul,
    bnp_point_at_infinity,
    bnp2_point_at_infinity,
    pairing,
)

const PAIRING_CHECK_DATA_LEN = 192;

func alt_bn128_add{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;
    let (__fp__, _) = get_fp_and_pc();

    // Gas
    let gas_cost = Uint(150);
    let err = charge_gas(gas_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    // Operation
    tempvar u256_zero = U256(new U256Struct(0, 0));
    tempvar u256_thirty_two = U256(new U256Struct(32, 0));
    tempvar u256_sixty_four = U256(new U256Struct(64, 0));
    tempvar u256_ninety_six = U256(new U256Struct(96, 0));
    let x0_bytes = buffer_read(data, u256_zero, u256_thirty_two);
    let y0_bytes = buffer_read(data, u256_thirty_two, u256_thirty_two);
    let x1_bytes = buffer_read(data, u256_sixty_four, u256_thirty_two);
    let y1_bytes = buffer_read(data, u256_ninety_six, u256_thirty_two);

    let x0_value = U256_from_be_bytes(x0_bytes);
    let y0_value = U256_from_be_bytes(y0_bytes);
    let x1_value = U256_from_be_bytes(x1_bytes);
    let y1_value = U256_from_be_bytes(y1_bytes);

    tempvar ALT_BN128_PRIME = U256(new U256Struct(alt_bn128.P_LOW_128, alt_bn128.P_HIGH_128));
    tempvar oog_err = new EthereumException(OutOfGasError);
    let is_x0_out_of_range = U256_le(ALT_BN128_PRIME, x0_value);
    if (is_x0_out_of_range.value != 0) {
        return oog_err;
    }
    let is_y0_out_of_range = U256_le(ALT_BN128_PRIME, y0_value);
    if (is_y0_out_of_range.value != 0) {
        return oog_err;
    }
    let is_x1_out_of_range = U256_le(ALT_BN128_PRIME, x1_value);
    if (is_x1_out_of_range.value != 0) {
        return oog_err;
    }
    let is_y1_out_of_range = U256_le(ALT_BN128_PRIME, y1_value);
    if (is_y1_out_of_range.value != 0) {
        return oog_err;
    }

    // Checks that point are on the curve
    let x0_uint384 = uint256_to_uint384([x0_value.value]);
    let y0_uint384 = uint256_to_uint384([y0_value.value]);
    let x1_uint384 = uint256_to_uint384([x1_value.value]);
    let y1_uint384 = uint256_to_uint384([y1_value.value]);
    tempvar p0 = G1Point(new G1PointStruct(x=U384(new x0_uint384), y=U384(new y0_uint384)));
    tempvar p1 = G1Point(new G1PointStruct(x=U384(new x1_uint384), y=U384(new y1_uint384)));
    tempvar a = U384(new UInt384(alt_bn128.A0, alt_bn128.A1, alt_bn128.A2, alt_bn128.A3));
    tempvar b = U384(new UInt384(alt_bn128.B0, alt_bn128.B1, alt_bn128.B2, alt_bn128.B3));
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));
    tempvar g = U384(new UInt384(alt_bn128.G0, alt_bn128.G1, alt_bn128.G2, alt_bn128.G3));

    // Checks verifying the points are on the curve.
    let point_inf = G1Point_zero();
    let is_p0_zero = G1Point__eq__(p0, point_inf);
    let is_p1_zero = G1Point__eq__(p1, point_inf);

    let pair_is_zero = is_p0_zero.value * is_p1_zero.value;
    if (pair_is_zero != 0) {
        let (buffer: felt*) = alloc();
        memset(buffer, 0, 64);
        tempvar output = Bytes(new BytesStruct(data=buffer, len=64));
        EvmImpl.set_output(output);
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    tempvar is_on_curve;
    tempvar point = p0;
    %{ is_point_on_curve %}
    if (is_on_curve == 0 and is_p0_zero.value == 0) {
        assert_not_on_curve(p0.value, a, b, modulus);
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    if (is_p0_zero.value == 0) {
        assert_on_curve(p0.value, a, b, modulus);
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    } else {
        // Point at infinity
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    }

    tempvar is_on_curve;
    tempvar point = p1;
    %{ is_point_on_curve %}
    tempvar is_p1_on_curve_uint384 = UInt384(is_on_curve, 0, 0, 0);

    if (is_on_curve == 0 and is_p1_zero.value == 0) {
        assert_not_on_curve(p1.value, a, b, modulus);
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    if (is_p1_zero.value == 0) {
        assert_on_curve(p1.value, a, b, modulus);
    } else {
        // Point at infinity
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    }

    let res = ec_add(p0, p1, a, modulus);
    let output = alt_bn128_G1Point__to_Bytes_be(res);
    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

func alt_bn128_mul{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;

    // Gas
    let gas_cost = Uint(6000);
    let err = charge_gas(gas_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    tempvar u256_zero = U256(new U256Struct(0, 0));
    tempvar u256_thirty_two = U256(new U256Struct(32, 0));
    tempvar u256_sixty_four = U256(new U256Struct(64, 0));
    let x0_bytes = buffer_read(data, u256_zero, u256_thirty_two);
    let y0_bytes = buffer_read(data, u256_thirty_two, u256_thirty_two);
    let k_bytes = buffer_read(data, u256_sixty_four, u256_thirty_two);

    let x0_value = U256_from_be_bytes(x0_bytes);
    let y0_value = U256_from_be_bytes(y0_bytes);
    let k_value = U256_from_be_bytes(k_bytes);

    tempvar ALT_BN128_PRIME = U256(new U256Struct(alt_bn128.P_LOW_128, alt_bn128.P_HIGH_128));
    // Check that x0 is within the interval [0, modulus)
    let is_x0_out_of_range = U256_le(ALT_BN128_PRIME, x0_value);
    if (is_x0_out_of_range.value != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }
    // Check that y0 is within the interval [0, modulus)
    let is_y0_out_of_range = U256_le(ALT_BN128_PRIME, y0_value);
    if (is_y0_out_of_range.value != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    // Check that p0 is on curve
    let x0_uint384 = uint256_to_uint384([x0_value.value]);
    let y0_uint384 = uint256_to_uint384([y0_value.value]);
    tempvar p0 = G1Point(new G1PointStruct(x=U384(new x0_uint384), y=U384(new y0_uint384)));

    let point_inf = G1Point_zero();
    let is_p0_zero = G1Point__eq__(p0, point_inf);
    // If P0 is point at infinity, return point at infinity.
    if (is_p0_zero.value != 0) {
        let (buffer: felt*) = alloc();
        memset(buffer, 0, 64);
        tempvar output = Bytes(new BytesStruct(data=buffer, len=64));
        EvmImpl.set_output(output);
        tempvar ok = cast(0, EthereumException*);
        return ok;
    }

    tempvar a = U384(new UInt384(alt_bn128.A0, alt_bn128.A1, alt_bn128.A2, alt_bn128.A3));
    tempvar b = U384(new UInt384(alt_bn128.B0, alt_bn128.B1, alt_bn128.B2, alt_bn128.B3));
    tempvar modulus = U384(new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3));
    tempvar g = U384(new UInt384(alt_bn128.G0, alt_bn128.G1, alt_bn128.G2, alt_bn128.G3));
    tempvar is_on_curve;
    tempvar point = p0;
    %{ is_point_on_curve %}
    if (is_on_curve == 0) {
        assert_not_on_curve(p0.value, a, b, modulus);
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    assert_on_curve(p0.value, a, b, modulus);

    // Operation
    let k_uint384 = uint256_to_uint384([k_value.value]);
    let res = ec_mul(p0, U384(new k_uint384), modulus);
    let output = alt_bn128_G1Point__to_Bytes_be(res);
    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

// @notice Writes the message data to the output
func alt_bn128_pairing_check{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;

    // Gas
    let (data_factor, rem) = divmod(data.value.len, PAIRING_CHECK_DATA_LEN);
    let gas_cost = Uint(34000 * data_factor + 45000);
    let err = charge_gas(gas_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    // Operation
    // Check if data length is a multiple of 192
    if (rem != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    // Initialize result to 1
    let start_result = BNF12_ONE();

    // Process each pair of points
    let pairs_count = data_factor;
    let (result, err) = process_point_pairs(data, pairs_count, 0, start_result);
    if (cast(err, felt) != 0) {
        return err;
    }

    // Check pairing and set output accordingly
    let one = BNF12_ONE();
    let is_one = BNF12__eq__(result, one);

    // Prepare output
    let (buffer: felt*) = alloc();
    if (is_one.value != 0) {
        memset(buffer, 0, 31);
        assert buffer[31] = 1;
    } else {
        memset(buffer, 0, 32);
    }

    tempvar output = Bytes(new BytesStruct(buffer, 32));
    EvmImpl.set_output(output);

    tempvar ok = cast(0, EthereumException*);
    return ok;
}

// Helper function to process pairs of points
func process_point_pairs{
    range_check_ptr,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    bitwise_ptr: BitwiseBuiltin*,
}(data: Bytes, total_pairs: felt, current_pair: felt, current_result: BNF12) -> (
    BNF12, EthereumException*
) {
    alloc_locals;
    if (current_pair == total_pairs) {
        return (current_result, cast(0, EthereumException*));
    }

    // Read coordinates for current pair
    let offset = current_pair * PAIRING_CHECK_DATA_LEN;
    tempvar u256_thirty_two = U256(new U256Struct(32, 0));

    // Read G1 point coordinates
    let x0_bytes = buffer_read(data, U256(new U256Struct(offset, 0)), u256_thirty_two);
    let y0_bytes = buffer_read(data, U256(new U256Struct(offset + 32, 0)), u256_thirty_two);

    // Read G2 point coordinates
    let x1_im_bytes = buffer_read(data, U256(new U256Struct(offset + 64, 0)), u256_thirty_two);
    let x1_re_bytes = buffer_read(data, U256(new U256Struct(offset + 96, 0)), u256_thirty_two);
    let y1_im_bytes = buffer_read(data, U256(new U256Struct(offset + 128, 0)), u256_thirty_two);
    let y1_re_bytes = buffer_read(data, U256(new U256Struct(offset + 160, 0)), u256_thirty_two);

    // Convert bytes to values
    let x0_value = U256_from_be_bytes(x0_bytes);
    let y0_value = U256_from_be_bytes(y0_bytes);
    let x1_im_value = U256_from_be_bytes(x1_im_bytes);
    let x1_re_value = U256_from_be_bytes(x1_re_bytes);
    let y1_im_value = U256_from_be_bytes(y1_im_bytes);
    let y1_re_value = U256_from_be_bytes(y1_re_bytes);

    // Check values are within field
    tempvar ALT_BN128_PRIME = U256(new U256Struct(alt_bn128.P_LOW_128, alt_bn128.P_HIGH_128));
    let is_x0_out_of_range = U256_le(ALT_BN128_PRIME, x0_value);
    let is_y0_out_of_range = U256_le(ALT_BN128_PRIME, y0_value);
    let is_x1_im_out_of_range = U256_le(ALT_BN128_PRIME, x1_im_value);
    let is_x1_re_out_of_range = U256_le(ALT_BN128_PRIME, x1_re_value);
    let is_y1_im_out_of_range = U256_le(ALT_BN128_PRIME, y1_im_value);
    let is_y1_re_out_of_range = U256_le(ALT_BN128_PRIME, y1_re_value);

    if (is_x0_out_of_range.value + is_y0_out_of_range.value + is_x1_im_out_of_range.value +
        is_x1_re_out_of_range.value + is_y1_im_out_of_range.value + is_y1_re_out_of_range.value != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return (current_result, err);
    }

    // Create points
    let x0_uint384 = uint256_to_uint384([x0_value.value]);
    let y0_uint384 = uint256_to_uint384([y0_value.value]);
    tempvar x_bnf = BNF(new BNFStruct(U384(new x0_uint384)));
    tempvar y_bnf = BNF(new BNFStruct(U384(new y0_uint384)));
    let (p, err) = bnp_init(x_bnf, y_bnf);
    if (cast(err, felt) != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return (current_result, err);
    }
    let x1_re_uint384 = uint256_to_uint384([x1_re_value.value]);
    let x1_im_uint384 = uint256_to_uint384([x1_im_value.value]);
    let y1_re_uint384 = uint256_to_uint384([y1_re_value.value]);
    let y1_im_uint384 = uint256_to_uint384([y1_im_value.value]);
    tempvar x_bnf2 = BNF2(new BNF2Struct(U384(new x1_re_uint384), U384(new x1_im_uint384)));
    tempvar y_bnf2 = BNF2(new BNF2Struct(U384(new y1_re_uint384), U384(new y1_im_uint384)));
    let (q, err) = bnp2_init(x_bnf2, y_bnf2);
    if (cast(err, felt) != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return (current_result, err);
    }

    // Subgroup checks
    tempvar curve_order = U384(new UInt384(alt_bn128.N0, alt_bn128.N1, alt_bn128.N2, alt_bn128.N3));
    let p_mul_order = bnp_mul_by(p, curve_order);
    let q_mul_order = bnp2_mul_by(q, curve_order);

    let p_inf = bnp_point_at_infinity();
    let q_inf = bnp2_point_at_infinity();

    let is_p_valid = BNP__eq__(p_mul_order, p_inf);
    let is_q_valid = BNP2__eq__(q_mul_order, q_inf);

    if (is_p_valid.value * is_q_valid.value == 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return (current_result, err);
    }

    let is_p_infinity = BNP__eq__(p, p_inf);
    let is_q_infinity = BNP2__eq__(q, q_inf);

    if (is_p_infinity.value * is_q_infinity.value == 0) {
        // Compute pairing and multiply with current result
        let pair_result = pairing(q, p);
        let new_result = bnf12_mul(current_result, pair_result);
        return process_point_pairs(data, total_pairs, current_pair + 1, new_result);
    }

    return process_point_pairs(data, total_pairs, current_pair + 1, current_result);
}

func alt_bn128_G1Point__to_Bytes_be{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    point: G1Point
) -> Bytes {
    alloc_locals;
    let (buffer: felt*) = alloc();
    felt252_to_bytes_be(point.value.x.value.d2, 8, buffer);
    felt252_to_bytes_be(point.value.x.value.d1, 12, buffer + 8);
    felt252_to_bytes_be(point.value.x.value.d0, 12, buffer + 20);
    with_attr error_message("alt_bn128_G1Point__to_Bytes_le: point.x.d3 != 0") {
        assert point.value.x.value.d3 = 0;
    }
    felt252_to_bytes_be(point.value.y.value.d2, 8, buffer + 32);
    felt252_to_bytes_be(point.value.y.value.d1, 12, buffer + 40);
    felt252_to_bytes_be(point.value.y.value.d0, 12, buffer + 52);
    with_attr error_message("alt_bn128_G1Point__to_Bytes_le: point.y.d3 != 0") {
        assert point.value.y.value.d3 = 0;
    }
    tempvar res = Bytes(new BytesStruct(data=buffer, len=64));
    return res;
}
