use std::collections::HashMap;

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

use crate::vm::hints::Hint;

pub const HINTS: &[fn() -> Hint] = &[bytes__eq__, b_le_a, fp_plus_2_or_0, nibble_remainder];

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
            let get_bytes_params = |name: &str| -> Result<
                (usize, cairo_vm::types::relocatable::Relocatable),
                HintError,
            > {
                let ptr = get_ptr_from_var_name(name, vm, ids_data, ap_tracking)?;
                let len_addr = (ptr + 1)?;

                let len_felt = vm.get_integer(len_addr)?.into_owned();
                let len = len_felt
                    .try_into()
                    .map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(len_felt)))?;

                let data = vm.get_relocatable(ptr)?;

                Ok((len, data))
            };

            let (self_len, self_data) = get_bytes_params("_self")?;
            let (other_len, other_data) = get_bytes_params("other")?;

            // Compare bytes until we find a difference
            for i in 0..std::cmp::min(self_len, other_len) {
                let self_byte = vm.get_integer((self_data + i)?)?.into_owned();

                let other_byte = vm.get_integer((other_data + i)?)?.into_owned();

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
            let a = get_integer_from_var_name("a", vm, ids_data, ap_tracking)?;
            let b = get_integer_from_var_name("b", vm, ids_data, ap_tracking)?;
            let result = usize::from(b <= a);
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

pub fn fp_plus_2_or_0() -> Hint {
    Hint::new(
        String::from("fp_plus_2_or_0"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let fp_offset = (vm.get_fp() + 2)?;
            let value_set = vm.get_maybe(&fp_offset);
            if value_set.is_none() {
                vm.insert_value(fp_offset, MaybeRelocatable::from(0))?;
            }
            Ok(())
        },
    )
}

pub fn nibble_remainder() -> Hint {
    Hint::new(
        String::from("memory[fp + 2] = to_felt_or_relocatable(ids.x.value.len % 2)"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let bytes_ptr = get_ptr_from_var_name("x", vm, ids_data, ap_tracking)?;
            let len = vm.get_integer((bytes_ptr + 1)?)?.into_owned();
            let len: usize =
                len.try_into().map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(len)))?;
            let remainder = len % 2;
            vm.insert_value((vm.get_fp() + 2)?, MaybeRelocatable::from(remainder))?;
            Ok(())
        },
    )
}
