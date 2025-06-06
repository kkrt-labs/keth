use std::{collections::HashMap, ops::Shl};

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{
            get_integer_from_var_name, get_ptr_from_var_name, insert_value_from_var_name,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::{
        errors::math_errors::MathError, exec_scope::ExecutionScopes, relocatable::MaybeRelocatable,
    },
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use num_bigint::BigUint;
use num_traits::One;

use crate::vm::hints::Hint;

pub const HINTS: &[fn() -> Hint] = &[
    felt252_to_bits_rev,
    felt252_to_bytes_le,
    felt252_to_bytes_be,
    value_len_mod_two,
    is_positive_hint,
    felt252_to_bytes4_le,
];

pub fn felt252_to_bytes_le() -> Hint {
    Hint::new(
        String::from("felt252_to_bytes_le"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get input values from Cairo
            let value = get_integer_from_var_name("value", vm, ids_data, ap_tracking)?;
            let len = get_integer_from_var_name("len", vm, ids_data, ap_tracking)?;
            let output_ptr = get_ptr_from_var_name("output", vm, ids_data, ap_tracking)?;

            let len: usize =
                len.try_into().map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(len)))?;

            let truncated_value = if len < 32 {
                // Create mask for truncation: (1 << (len * 8)) - 1
                let one = BigUint::from(1u32);
                let shifted = one.clone() << (len * 8);
                let mask = shifted - one;
                felt252_bit_and(value, mask.into())?
            } else {
                value
            };

            // Convert to bytes and write to memory
            let bytes = truncated_value
                .to_bytes_le()
                .split_at(len)
                .0
                .iter()
                .map(|b| MaybeRelocatable::Int((*b).into()))
                .collect::<Vec<MaybeRelocatable>>();
            vm.segments.write_arg(output_ptr, &bytes)?;
            Ok(())
        },
    )
}

pub fn felt252_to_bytes_be() -> Hint {
    Hint::new(
        String::from("felt252_to_bytes_be"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get input values from Cairo
            let value = get_integer_from_var_name("value", vm, ids_data, ap_tracking)?;
            let len = get_integer_from_var_name("len", vm, ids_data, ap_tracking)?;
            let output_ptr = get_ptr_from_var_name("output", vm, ids_data, ap_tracking)?;

            let len: usize =
                len.try_into().map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(len)))?;

            let truncated_value = if len < 32 {
                // Create mask for truncation: (1 << (len * 8)) - 1
                let one = BigUint::from(1u32);
                let shifted = one.clone() << (len * 8);
                let mask = shifted - one;
                felt252_bit_and(value, mask.into())?
            } else {
                value
            };

            // Convert to bytes and write to memory
            let bytes = truncated_value
                .to_bytes_be()
                .split_at(32 - len)
                .1
                .iter()
                .map(|b| MaybeRelocatable::Int((*b).into()))
                .collect::<Vec<MaybeRelocatable>>();
            vm.segments.write_arg(output_ptr, &bytes)?;

            Ok(())
        },
    )
}

pub fn is_positive_hint() -> Hint {
    Hint::new(
        String::from("is_positive_hint"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let value = get_integer_from_var_name("value", vm, ids_data, ap_tracking)?;
            let is_positive =
                if value <= Felt252::from(Felt252::MAX.to_biguint() / 2_u32) { 1 } else { 0 };
            insert_value_from_var_name("is_positive", is_positive, vm, ids_data, ap_tracking)
        },
    )
}

pub fn value_len_mod_two() -> Hint {
    Hint::new(
        String::from("value_len_mod_two"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let len = get_integer_from_var_name("len", vm, ids_data, ap_tracking)?;
            let len_biguint = len.to_biguint();
            let remainder = len_biguint % BigUint::from(2u64);
            insert_value_from_var_name(
                "remainder",
                Felt252::from(remainder),
                vm,
                ids_data,
                ap_tracking,
            )
        },
    )
}

/// Source: https://github.com/lambdaclass/cairo-vm/tree/main/vm/src/vm/runners/builtin_runner/bitwise.rs#L71-L107
fn felt252_bit_and(num_x: Felt252, num_y: Felt252) -> Result<Felt252, HintError> {
    let to_limbs = |x: &Felt252| -> Result<[u64; 4], HintError> {
        const LEADING_BITS: u64 = 0xf800000000000000;
        let limbs = x.to_le_digits();
        if limbs[3] & LEADING_BITS != 0 {
            return Err(HintError::CustomHint(Box::from("IntegerBiggerThanPowerOfTwo".to_owned())));
        }
        Ok(limbs)
    };
    let (limbs_x, limbs_y) = (to_limbs(&num_x)?, to_limbs(&num_y)?);
    let mut limbs_xy = [0u64; 4];
    for (xy, (x, y)) in limbs_xy.iter_mut().zip(limbs_x.into_iter().zip(limbs_y.into_iter())) {
        *xy = x & y;
    }
    let mut bytes_xy = [0u8; 32];
    bytes_xy[..8].copy_from_slice(limbs_xy[0].to_le_bytes().as_slice());
    bytes_xy[8..16].copy_from_slice(limbs_xy[1].to_le_bytes().as_slice());
    bytes_xy[16..24].copy_from_slice(limbs_xy[2].to_le_bytes().as_slice());
    bytes_xy[24..].copy_from_slice(limbs_xy[3].to_le_bytes().as_slice());
    Ok(Felt252::from_bytes_le_slice(&bytes_xy))
}

pub fn felt252_to_bits_rev() -> Hint {
    Hint::new(
        String::from("felt252_to_bits_rev"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get input values from Cairo
            let value = get_integer_from_var_name("value", vm, ids_data, ap_tracking)?;
            let len = get_integer_from_var_name("len", vm, ids_data, ap_tracking)?;
            let dst_ptr = get_ptr_from_var_name("dst", vm, ids_data, ap_tracking)?;

            let len_usize: usize =
                len.try_into().map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(len)))?;

            // Handle length == 0 case separately
            if len_usize == 0 {
                insert_value_from_var_name("bits_used", Felt252::ZERO, vm, ids_data, ap_tracking)?;
                // No bits to write for len 0, dst_ptr remains untouched
                return Ok(());
            }

            let value_biguint = value.to_biguint();

            // Ensure we only work with the bits relevant to the requested length
            // Create mask: (1 << len_usize) - 1
            let mask = BigUint::one().shl(len_usize) - BigUint::one();
            let value_masked = value_biguint & mask;

            // Calculate bits_used based on the masked value's actual bit length
            let bits_used = value_masked.bits() as usize;
            let bits_used_to_assign = std::cmp::min(bits_used, len_usize);
            insert_value_from_var_name(
                "bits_used",
                Felt252::from(bits_used_to_assign),
                vm,
                ids_data,
                ap_tracking,
            )?;

            // Generate the 'bits_used' bits in reversed order (LSB first in the vec)
            let bits: Vec<MaybeRelocatable> = (0..bits_used)
                .map(|i| {
                    // Check the i-th bit of the masked value
                    Felt252::from(value_masked.bit(i as u64)).into()
                })
                .collect();

            // Write the bits to memory starting at dst_ptr
            vm.segments.load_data(dst_ptr, &bits)?;
            Ok(())
        },
    )
}

pub fn felt252_to_bytes4_le() -> Hint {
    Hint::new(
        String::from("felt252_to_bytes4_le"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let value = get_integer_from_var_name("value", vm, ids_data, ap_tracking)?;
            let num_words_felt = get_integer_from_var_name("num_words", vm, ids_data, ap_tracking)?;
            let dst_ptr = get_ptr_from_var_name("output", vm, ids_data, ap_tracking)?;

            let num_words: usize = num_words_felt
                .try_into()
                .map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(num_words_felt)))?;

            let value_biguint = value.to_biguint();
            let mut output_felts: Vec<MaybeRelocatable> = Vec::with_capacity(num_words);
            let mask_32_bit = BigUint::from(0xFFFFFFFFu32);

            for i in 0..num_words {
                let shifted_val = value_biguint.clone() >> (i * 32);
                let word_biguint = shifted_val & mask_32_bit.clone();
                output_felts.push(MaybeRelocatable::Int(Felt252::from(word_biguint)));
            }

            vm.segments.write_arg(dst_ptr, &output_felts)?;
            Ok(())
        },
    )
}
