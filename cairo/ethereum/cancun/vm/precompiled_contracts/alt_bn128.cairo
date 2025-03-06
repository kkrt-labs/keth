from starkware.cairo.common.cairo_builtins import (
    BitwiseBuiltin,
    KeccakBuiltin,
    ModBuiltin,
    PoseidonBuiltin,
    UInt384,
)
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memset import memset
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import OutOfGasError
from ethereum.utils.numeric import ceil32, divmod, U256_from_be_bytes, U256_le
from ethereum.cancun.vm.gas import GasConstants, charge_gas
from ethereum_types.numeric import Uint, U256, U256Struct
from ethereum_types.bytes import Bytes, BytesStruct
from ethereum.cancun.vm.memory import buffer_read
from cairo_ec.curve.alt_bn128 import alt_bn128
from cairo_ec.ec_ops import ec_add, ec_mul
from cairo_ec.curve.g1_point import G1Point, G1Point__eq__
from cairo_ec.circuits.ec_ops_compiled import (
    assert_x_is_on_curve,
    assert_not_on_curve,
    assert_on_curve,
)
from cairo_ec.uint384 import uint256_to_uint384
from cairo_core.maths import felt252_to_bytes_be
from starkware.cairo.common.registers import get_fp_and_pc

func alt_bn128_add{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;

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
    let p0 = G1Point(x=x0_uint384, y=y0_uint384);
    let p1 = G1Point(x=x1_uint384, y=y1_uint384);
    tempvar a = new UInt384(alt_bn128.A0, alt_bn128.A1, alt_bn128.A2, alt_bn128.A3);
    tempvar b = new UInt384(alt_bn128.B0, alt_bn128.B1, alt_bn128.B2, alt_bn128.B3);
    tempvar modulus = new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3);
    tempvar g = new UInt384(alt_bn128.G0, alt_bn128.G1, alt_bn128.G2, alt_bn128.G3);

    // Checks verifying the points are on the curve.
    let point_inf = G1Point(x=UInt384(0, 0, 0, 0), y=UInt384(0, 0, 0, 0));
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
    tempvar is_p0_on_curve_uint384 = UInt384(is_on_curve, 0, 0, 0);
    if (is_on_curve == 0 and is_p0_zero.value == 0) {
        assert_not_on_curve(new p0.x, new p0.y, a, b, modulus);
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    if (is_p0_zero.value == 0) {
        assert_on_curve(new p0.x, new p0.y, a, b, modulus);
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
        assert_not_on_curve(new p1.x, new p1.y, a, b, modulus);
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    if (is_p1_zero.value == 0) {
        assert_on_curve(new p1.x, new p1.y, a, b, modulus);
    } else {
        // Point at infinity
        tempvar range_check96_ptr = range_check96_ptr;
        tempvar add_mod_ptr = add_mod_ptr;
        tempvar mul_mod_ptr = mul_mod_ptr;
    }

    let res = ec_add(p0, p1, [a], [modulus]);
    let output = alt_bn128_G1Point__to_Bytes_be(res);
    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

func alt_bn128_mul{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
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
    let p0 = G1Point(x=x0_uint384, y=y0_uint384);

    let point_inf = G1Point(x=UInt384(0, 0, 0, 0), y=UInt384(0, 0, 0, 0));
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

    tempvar a = new UInt384(alt_bn128.A0, alt_bn128.A1, alt_bn128.A2, alt_bn128.A3);
    tempvar b = new UInt384(alt_bn128.B0, alt_bn128.B1, alt_bn128.B2, alt_bn128.B3);
    tempvar modulus = new UInt384(alt_bn128.P0, alt_bn128.P1, alt_bn128.P2, alt_bn128.P3);
    tempvar g = new UInt384(alt_bn128.G0, alt_bn128.G1, alt_bn128.G2, alt_bn128.G3);
    tempvar is_on_curve;
    tempvar point = p0;
    %{ is_point_on_curve %}
    tempvar is_p0_on_curve_uint384 = UInt384(is_on_curve, 0, 0, 0);
    if (is_on_curve == 0) {
        assert_not_on_curve(new p0.x, new p0.y, a, b, modulus);
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    assert_on_curve(new p0.x, new p0.y, a, b, modulus);

    // Operation
    let k_uint384 = uint256_to_uint384([k_value.value]);
    let res = ec_mul(p0, k_uint384, [modulus]);
    let output = alt_bn128_G1Point__to_Bytes_be(res);
    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

// @notice Writes the message data to the output
func alt_bn128_pairing_check{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: KeccakBuiltin*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;

    // Gas
    let (data_factor, rem) = divmod(data.value.len, 192);
    let gas_cost = Uint(34000 * data_factor + 45000);
    let err = charge_gas(gas_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    // Operation
    if (rem != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }

    tempvar data = data;
    tempvar error: EthereumException*;
    tempvar output: Bytes;
    %{ alt_bn128_pairing_check_hint %}

    if (cast(error, felt) != 0) {
        return error;
    }

    EvmImpl.set_output(output);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}

func alt_bn128_G1Point__to_Bytes_be{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    point: G1Point
) -> Bytes {
    alloc_locals;
    let (buffer: felt*) = alloc();
    felt252_to_bytes_be(point.x.d2, 8, buffer);
    felt252_to_bytes_be(point.x.d1, 12, buffer + 8);
    felt252_to_bytes_be(point.x.d0, 12, buffer + 20);
    with_attr error_message("alt_bn128_G1Point__to_Bytes_le: point.x.d3 != 0") {
        assert point.x.d3 = 0;
    }
    felt252_to_bytes_be(point.y.d2, 8, buffer + 32);
    felt252_to_bytes_be(point.y.d1, 12, buffer + 40);
    felt252_to_bytes_be(point.y.d0, 12, buffer + 52);
    with_attr error_message("alt_bn128_G1Point__to_Bytes_le: point.y.d3 != 0") {
        assert point.y.d3 = 0;
    }
    tempvar res = Bytes(new BytesStruct(data=buffer, len=64));
    return res;
}
