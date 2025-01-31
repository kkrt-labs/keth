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
            let base = get_integer_from_var_name("base", vm, ids_data, ap_tracking)?;
            let bound = get_integer_from_var_name("bound", vm, ids_data, ap_tracking)?;
            let output_ptr = get_ptr_from_var_name("output", vm, ids_data, ap_tracking)?;

            let len: usize =
                len.try_into().map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(len)))?;

            let mut current_value = value;

            for i in 0..len {
                let res_i = current_value.mod_floor(&base.try_into().unwrap());
                if res_i >= bound {
                    return Err(HintError::CustomHint(Box::from(format!(
                        "felt252_to_bytes_le: Limb {} is out of range.",
                        res_i
                    ))));
                }
                vm.insert_value((output_ptr + i)?, MaybeRelocatable::from(res_i))?;
                current_value = current_value.floor_div(&base.try_into().unwrap());
            }

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
            let base = get_integer_from_var_name("base", vm, ids_data, ap_tracking)?;
            let bound = get_integer_from_var_name("bound", vm, ids_data, ap_tracking)?;
            let output_ptr = get_ptr_from_var_name("output", vm, ids_data, ap_tracking)?;

            let len: usize =
                len.try_into().map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(len)))?;

            let mut current_value = value;

            // Main difference is iterating in reverse order for big-endian
            for i in (0..len).rev() {
                let res_i = current_value.mod_floor(&base.try_into().unwrap());
                if res_i >= bound {
                    return Err(HintError::CustomHint(Box::from(format!(
                        "felt252_to_bytes_be: Limb {} is out of range.",
                        res_i
                    ))));
                }
                vm.insert_value((output_ptr + i)?, MaybeRelocatable::from(res_i))?;
                current_value = current_value.floor_div(&base.try_into().unwrap());
            }

            Ok(())
        },
    )
}
