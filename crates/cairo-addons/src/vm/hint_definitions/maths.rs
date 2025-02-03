use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{get_integer_from_var_name, get_ptr_from_var_name},
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::{
        errors::math_errors::MathError, exec_scope::ExecutionScopes, relocatable::MaybeRelocatable,
    },
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};

use crate::vm::hints::Hint;

pub const HINTS: &[fn() -> Hint] = &[felt252_to_bytes_le, felt252_to_bytes_be];

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
                let mask = (1_u128 << (len * 8)) - 1;
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
                let mask = (1_u128 << (len * 8)) - 1;
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
