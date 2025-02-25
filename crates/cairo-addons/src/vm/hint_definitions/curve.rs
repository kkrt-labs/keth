use std::{cmp::min, collections::HashMap};

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{
            get_integer_from_var_name, get_ptr_from_var_name, get_relocatable_from_var_name,
            insert_value_from_var_name,
        },
        hint_processor_definition::HintReference,
    },
    math_utils::pow2_const,
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use garaga_rs::{
    calldata::msm_calldata::msm_calldata_builder,
    definitions::{
        CurveID, CurveParamsProvider, FieldElement, SECP256K1PrimeField,
        SECP256K1_PRIME_FIELD_ORDER,
    },
    ecip::core::neg_3_base_le,
    io::element_to_biguint,
};
use num_bigint::BigUint;
use num_traits::{pow, One, Zero};

use crate::vm::{
    hint_utils::{
        write_collection_from_var_name, write_collection_to_addr, write_result_to_ap, Uint256,
        Uint384,
    },
    hints::Hint,
};

pub const HINTS: &[fn() -> Hint] = &[
    build_msm_hints_and_fill_memory,
    compute_y_from_x_hint,
    fill_add_mod_mul_mod_builtin_batch_one,
    decompose_scalar_to_neg3_base,
    fill_add_mod_mul_mod_builtin_batch_117_108,
    is_point_on_curve,
];

/// Builds Multi-Scalar Multiplication (MSM) hints and fills memory for elliptic curve operations.
///
/// This function processes point coordinates and scalar values to prepare data for MSM operations
/// on the secp256k1 curve. It:
///
/// 1. Extracts point coordinates (x,y) and scalar values (u1,u2)
/// 2. Builds MSM calldata using the curve generator point G(g_x,g_y) and input point R(x,y)
/// 3. Processes the calldata into:
///    - q_low_high_high_shifted components for point arithmetic
///    - RLC (Random Linear Combination) components for efficient computation
/// 4. Fills the VM memory at specific offsets with the processed components
///
/// # Arguments
/// * r_point - A point R on the curve with coordinates (x,y)
/// * u1 - First scalar value for multiplication
/// * u2 - Second scalar value for multiplication
/// * range_check96_ptr - Pointer to range check memory region
///
/// # Memory Layout
/// The function writes to two main memory regions:
/// 1. RLC components: Written at range_check96_ptr + (4 * N_LIMBS + 4)
/// 2. Q components: Written at range_check96_ptr + (50 * N_LIMBS + 4)
///
/// # Errors
/// Returns an error if:
/// - Cannot extract point coordinates or scalar values
/// - MSM calldata building fails
/// - RLC components have invalid length
/// - Memory writing operations fail
pub fn build_msm_hints_and_fill_memory() -> Hint {
    Hint::new(
        String::from("build_msm_hints_and_fill_memory"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            const N_LIMBS: usize = 4;
            let r_point_addr = get_relocatable_from_var_name("r_point", vm, ids_data, ap_tracking)?;
            let x = Uint384::from_base_addr(r_point_addr, "r_point.x", vm)?.pack();
            let y =
                Uint384::from_base_addr((r_point_addr + N_LIMBS).unwrap(), "r_point.y", vm)?.pack();

            let g_x = element_to_biguint(&SECP256K1PrimeField::get_curve_params().g_x);
            let g_y = element_to_biguint(&SECP256K1PrimeField::get_curve_params().g_y);

            let u1 = Uint256::from_var_name("u1", vm, ids_data, ap_tracking)?.pack();
            let u2 = Uint256::from_var_name("u2", vm, ids_data, ap_tracking)?.pack();

            let values = vec![g_x, g_y, x, y];
            let scalars = vec![u1, u2];

            let curve_id = CurveID::SECP256K1;
            let calldata_w_len = msm_calldata_builder(
                &values,
                &scalars,
                curve_id as usize,
                false,
                false,
                false,
                false,
            )
            .map_err(|e| {
                HintError::CustomHint(format!("Error building MSM calldata: {}", e).into())
            })?;
            let calldata = calldata_w_len[1..].to_vec();

            let points_offset = 3 * 2 * N_LIMBS;
            let q_low_high_high_shifted = calldata[..points_offset].to_vec();
            let mut calldata_rest = calldata[points_offset..].to_vec();

            // Process 4 arrays of RLC components
            let mut rlc_components = Vec::<BigUint>::with_capacity((18 + 4 * 2) * N_LIMBS);
            for _ in 0..4 {
                let array_len: usize = calldata_rest.remove(0).try_into().map_err(|_| {
                    HintError::CustomHint("Failed to convert array length to usize".into())
                })?;
                let slice_len = min(array_len * N_LIMBS, calldata_rest.len());
                rlc_components.extend(calldata_rest[..slice_len].iter().cloned());
                calldata_rest = calldata_rest[slice_len..].to_vec();
            }

            const EXPECTED_LEN: usize = (18 + 4 * 2) * N_LIMBS;
            if rlc_components.len() != EXPECTED_LEN {
                return Err(HintError::CustomHint(
                    format!(
                        "Invalid RLC components length: expected {}, got {}",
                        EXPECTED_LEN,
                        rlc_components.len()
                    )
                    .into(),
                ));
            }

            // Fill memory
            let range_check96_ptr =
                get_ptr_from_var_name("range_check96_ptr", vm, ids_data, ap_tracking)?;
            let memory_offset = 28;

            let offset =
                (range_check96_ptr.segment_index, range_check96_ptr.offset + memory_offset).into();
            write_collection_to_addr(offset, &rlc_components, vm)?;

            let offset = range_check96_ptr + (46 * N_LIMBS + memory_offset);
            write_collection_to_addr(offset.unwrap(), &q_low_high_high_shifted, vm)?;
            Ok(())
        },
    )
}

pub fn compute_y_from_x_hint() -> Hint {
    Hint::new(
        String::from("compute_y_from_x_hint"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let a = Uint384::from_var_name("a", vm, ids_data, ap_tracking)?.pack();
            let b = Uint384::from_var_name("b", vm, ids_data, ap_tracking)?.pack();
            let p = Uint384::from_var_name("p", vm, ids_data, ap_tracking)?.pack();
            let g = Uint384::from_var_name("g", vm, ids_data, ap_tracking)?.pack();
            let x = Uint384::from_var_name("x", vm, ids_data, ap_tracking)?.pack();
            let v = get_integer_from_var_name("v", vm, ids_data, ap_tracking)?.to_biguint();

            let rhs = (pow(x.clone(), 3) + a * x + b) % p.clone();

            // Currently, only the secp256k1 field is supported
            let (rhs_felt, g_felt) = if p.to_str_radix(16).to_uppercase() ==
                SECP256K1_PRIME_FIELD_ORDER.to_hex()
            {
                let rhs_felt =
                    FieldElement::<SECP256K1PrimeField>::from_hex_unchecked(&rhs.to_str_radix(16));
                let g_felt =
                    FieldElement::<SECP256K1PrimeField>::from_hex_unchecked(&g.to_str_radix(16));
                (rhs_felt, g_felt)
            } else {
                panic!("Unsupported field: {}", p.to_str_radix(16).to_uppercase());
            };

            let is_on_curve = is_quad_residue(&rhs, &p);
            let square_root = if is_on_curve {
                let sqrt_felt = rhs_felt.sqrt().unwrap().0;
                let has_same_parity = (v % 2_u32) == (element_to_biguint(&sqrt_felt) % 2_u32);
                if has_same_parity {
                    sqrt_felt
                } else {
                    -sqrt_felt
                }
            } else {
                (rhs_felt * g_felt).sqrt().unwrap().0
            };

            let sqrt_biguint = element_to_biguint(&square_root);
            Uint384::split(&sqrt_biguint).insert_from_var_name(
                "y_try",
                vm,
                ids_data,
                ap_tracking,
            )?;
            write_collection_from_var_name(
                "is_on_curve",
                &[is_on_curve.into(), Felt252::ZERO, Felt252::ZERO, Felt252::ZERO],
                vm,
                ids_data,
                ap_tracking,
            )?;
            Ok(())
        },
    )
}

// Implementation adapted from lambdaclass' CairoVM
// Conditions:
// * a >= 0 < prime (other cases omitted)
fn is_quad_residue(a: &BigUint, p: &BigUint) -> bool {
    a.is_zero() || a.is_one() || a.modpow(&(p / 2_u32), p).is_one()
}

pub fn fill_add_mod_mul_mod_builtin_batch_one() -> Hint {
    Hint::new(
        String::from("fill_add_mod_mul_mod_builtin_batch_one"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get pointers, converting Result to Option
            let add_mod_ptr = get_ptr_from_var_name("add_mod_ptr", vm, ids_data, ap_tracking)
                .ok()
                .map(|ptr| (ptr, 1));

            let mul_mod_ptr = get_ptr_from_var_name("mul_mod_ptr", vm, ids_data, ap_tracking)
                .ok()
                .map(|ptr| (ptr, 1));

            // Fill memory with mod builtin values
            vm.mod_builtin_fill_memory(add_mod_ptr, mul_mod_ptr, Some(1))
                .map_err(HintError::Internal)
        },
    )
}

pub fn fill_add_mod_mul_mod_builtin_batch_117_108() -> Hint {
    Hint::new(
        String::from("fill_add_mod_mul_mod_builtin_batch_117_108"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get pointers, converting Result to Option
            let add_mod_ptr = get_ptr_from_var_name("add_mod_ptr", vm, ids_data, ap_tracking)
                .ok()
                .map(|ptr| (ptr, 117));

            let mul_mod_ptr = get_ptr_from_var_name("mul_mod_ptr", vm, ids_data, ap_tracking)
                .ok()
                .map(|ptr| (ptr, 108));

            // Fill memory with mod builtin values
            vm.mod_builtin_fill_memory(add_mod_ptr, mul_mod_ptr, Some(1))
                .map_err(HintError::Internal)
        },
    )
}

pub fn decompose_scalar_to_neg3_base() -> Hint {
    Hint::new(
        String::from("decompose_scalar_to_neg3_base"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let scalar = get_integer_from_var_name("scalar", vm, ids_data, ap_tracking)?;
            assert!(Felt252::ZERO <= scalar && scalar < pow2_const(128));
            let mut digits = neg_3_base_le(&scalar.to_biguint());
            digits.extend(vec![0; 82 - digits.len()]);

            write_collection_from_var_name("digits", &digits, vm, ids_data, ap_tracking)?;
            insert_value_from_var_name("d0", Felt252::from(digits[0]), vm, ids_data, ap_tracking)?;

            write_result_to_ap(true, 0, vm)?;

            Ok(())
        },
    )
}

pub fn is_point_on_curve() -> Hint {
    Hint::new(
        String::from("is_point_on_curve"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let point_addr = get_relocatable_from_var_name("point", vm, ids_data, ap_tracking)?;
            let x = Uint384::from_base_addr(point_addr, "point.x", vm)?.pack();
            let y = Uint384::from_base_addr((point_addr + 4_usize).unwrap(), "point.y", vm)?.pack();
            let a = Uint384::from_var_name("a", vm, ids_data, ap_tracking)?.pack();
            let b = Uint384::from_var_name("b", vm, ids_data, ap_tracking)?.pack();
            let modulus = Uint384::from_var_name("modulus", vm, ids_data, ap_tracking)?.pack();

            let rhs = (pow(x.clone(), 3) + a * x + b) % modulus.clone();
            let lhs = (pow(y.clone(), 2)) % modulus;
            let is_on_curve = rhs == lhs;

            insert_value_from_var_name(
                "is_on_curve",
                Felt252::from(is_on_curve),
                vm,
                ids_data,
                ap_tracking,
            )?;
            Ok(())
        },
    )
}
