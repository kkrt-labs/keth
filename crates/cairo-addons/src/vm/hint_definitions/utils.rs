use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{
            get_maybe_relocatable_from_var_name, get_ptr_from_var_name, insert_value_from_var_name,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::{exec_scope::ExecutionScopes, relocatable::MaybeRelocatable},
    vm::{
        errors::{hint_errors::HintError, memory_errors::MemoryError},
        vm_core::VirtualMachine,
    },
    Felt252,
};

use crate::vm::hints::Hint;

#[allow(non_snake_case)]
pub fn bytes__eq__() -> Hint {
    Hint::new(
        String::from("Bytes__eq__"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get self bytes parameters
            let self_ptr = get_ptr_from_var_name("_self", vm, ids_data, ap_tracking)?;
            let self_len_addr = (self_ptr + 1)?;
            let self_len = vm.get_maybe(&self_len_addr).ok_or_else(|| {
                HintError::Memory(MemoryError::UnknownMemoryCell(Box::new(self_len_addr)))
            })?;
            let self_data = vm.get_maybe(&self_ptr).ok_or_else(|| {
                HintError::Memory(MemoryError::UnknownMemoryCell(Box::new(self_ptr)))
            })?;

            // Get other bytes parameters
            let other_ptr = get_ptr_from_var_name("other", vm, ids_data, ap_tracking)?;
            let other_len_addr = (other_ptr + 1)?;
            let other_len = vm.get_maybe(&other_len_addr).ok_or_else(|| {
                HintError::Memory(MemoryError::UnknownMemoryCell(Box::new(other_len_addr)))
            })?;
            let other_data = vm.get_maybe(&other_ptr).ok_or_else(|| {
                HintError::Memory(MemoryError::UnknownMemoryCell(Box::new(other_ptr)))
            })?;

            // Convert lengths to usize
            let self_len = self_len
                .get_int()
                .ok_or_else(|| HintError::IdentifierNotInteger(Box::from("self_len")))?
                .try_into()
                .unwrap();
            let other_len = other_len
                .get_int()
                .ok_or_else(|| HintError::IdentifierNotInteger(Box::from("other_len")))?
                .try_into()
                .unwrap();

            // Get data pointers
            let self_data = self_data
                .get_relocatable()
                .ok_or_else(|| HintError::IdentifierNotRelocatable(Box::from("self_data")))?;
            let other_data = other_data
                .get_relocatable()
                .ok_or_else(|| HintError::IdentifierNotRelocatable(Box::from("other_data")))?;

            // Compare bytes until we find a difference
            for i in 0..std::cmp::min(self_len, other_len) {
                let self_bytes_addr = (self_data + i)?;
                let self_byte = vm.get_maybe(&self_bytes_addr).ok_or_else(|| {
                    HintError::Memory(MemoryError::UnknownMemoryCell(Box::new(self_bytes_addr)))
                })?;
                let other_bytes_addr = (other_data + i)?;
                let other_byte = vm.get_maybe(&other_bytes_addr).ok_or_else(|| {
                    HintError::Memory(MemoryError::UnknownMemoryCell(Box::new(other_bytes_addr)))
                })?;

                if self_byte != other_byte {
                    // Found difference - set is_diff=1 and diff_index=i
                    insert_value_from_var_name(
                        "is_diff",
                        MaybeRelocatable::from(1),
                        vm,
                        ids_data,
                        ap_tracking,
                    )?;
                    insert_value_from_var_name(
                        "diff_index",
                        MaybeRelocatable::from(i),
                        vm,
                        ids_data,
                        ap_tracking,
                    )?;
                    return Ok(());
                }
            }

            // No differences found in common prefix
            // Lengths were checked before this hint
            insert_value_from_var_name(
                "is_diff",
                MaybeRelocatable::from(0),
                vm,
                ids_data,
                ap_tracking,
            )?;
            insert_value_from_var_name(
                "diff_index",
                MaybeRelocatable::from(0),
                vm,
                ids_data,
                ap_tracking,
            )?;
            Ok(())
        },
    )
}

pub fn b_le_a() -> Hint {
    Hint::new(
        String::from("b_le_a"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let a = get_maybe_relocatable_from_var_name("a", vm, ids_data, ap_tracking)?;
            let b = get_maybe_relocatable_from_var_name("b", vm, ids_data, ap_tracking)?;
            let result = if b <= a { 1 } else { 0 };
            insert_value_from_var_name(
                "is_min_b",
                MaybeRelocatable::from(result),
                vm,
                ids_data,
                ap_tracking,
            )?;
            Ok(())
        },
    )
}
