use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{get_ptr_from_var_name, insert_value_from_var_name},
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::{exec_scope::ExecutionScopes, relocatable::Relocatable},
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use num_traits::Zero;

use crate::vm::hints::Hint;

pub const HINTS: &[fn() -> Hint] = &[find_two_non_null_subnodes];

/// Helper function to check if a pointer to a sequence (like Bytes)
/// points to a structure with a non-zero length at offset 1.
fn is_non_empty_sequence(vm: &VirtualMachine, struct_ptr: Relocatable) -> bool {
    // Length is expected at offset 1
    let len_addr = match struct_ptr + 1 {
        Ok(addr) => addr,
        Err(_) => return false, // Address calculation error
    };
    let len_val = match vm.get_integer(len_addr) {
        Ok(val) => val,
        Err(..) => return false, // Length value not in memory
    };
    // Check if length is an integer and not zero
    !len_val.into_owned().is_zero()
}

pub fn find_two_non_null_subnodes() -> Hint {
    Hint::new(
        String::from("find_two_non_null_subnodes"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get `subnodes_ptr` from ids
            let subnodes_ptr = get_ptr_from_var_name("subnodes_ptr", vm, ids_data, ap_tracking)?;

            let mut non_null_indices: Vec<Felt252> = Vec::with_capacity(2);

            // Check each of the 16 possible indices (0-15)
            for idx in 0..16u32 {
                // Get the pointer to the subnode structure at this index
                let subnode_ptr_addr = (subnodes_ptr + idx).map_err(|_| {
                    HintError::CustomHint(Box::from(format!(
                        "Invalid pointer: {} + {}",
                        subnodes_ptr, idx
                    )))
                })?;

                // The subnode pointer itself must be a relocatable (pointing to the ExtendedEnum)
                let inner_ptr_addr = match vm.get_relocatable(subnode_ptr_addr) {
                    Ok(addr) => addr,
                    Err(..) => continue, // Subnode pointer is null or not a relocatable
                };

                // Case 1: Check if subnode is a non-null embedded node (Sequence*)
                // Sequence* is at offset 0 of the ExtendedEnum struct
                let is_sequence = vm
                    .get_relocatable(inner_ptr_addr)
                    .map_or(false, |seq_ptr| is_non_empty_sequence(vm, seq_ptr));

                // Case 2: Check if subnode is a non-null digest (Bytes*)
                // Bytes* is at offset 2 of the ExtendedEnum struct
                let bytes_ptr_addr = (inner_ptr_addr + 2u32).map_err(|_| {
                    HintError::CustomHint(Box::from(format!(
                        "Invalid pointer: {} + {}",
                        inner_ptr_addr, 2u32
                    )))
                })?;
                let is_bytes = vm
                    .get_relocatable(bytes_ptr_addr)
                    .map_or(false, |bytes_ptr| is_non_empty_sequence(vm, bytes_ptr));

                // If it's either a non-null sequence or non-null bytes, record the index
                if is_sequence || is_bytes {
                    non_null_indices.push(idx.into());
                    // If we found 2 non-null subnodes, we can stop
                    if non_null_indices.len() >= 2 {
                        break;
                    }
                }
            }

            let first_non_null_index =
                if !non_null_indices.is_empty() { non_null_indices[0] } else { Felt252::ZERO };

            let second_non_null_index =
                if non_null_indices.len() > 1 { non_null_indices[1] } else { Felt252::ZERO };

            insert_value_from_var_name(
                "first_non_null_index",
                first_non_null_index,
                vm,
                ids_data,
                ap_tracking,
            )?;

            insert_value_from_var_name(
                "second_non_null_index",
                second_non_null_index,
                vm,
                ids_data,
                ap_tracking,
            )?;

            Ok(())
        },
    )
}
