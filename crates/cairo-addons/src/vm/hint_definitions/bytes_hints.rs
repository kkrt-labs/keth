use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{
            get_integer_from_var_name, get_ptr_from_var_name, insert_value_from_var_name,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};

use crate::vm::hints::Hint;

pub const HINTS: &[fn() -> Hint] = &[
    bytes_len_less_than_8,
    remaining_bytes_greater_than_8,
    remaining_bytes_jmp_offset,
    bytes_len_less_than_4,
    remaining_bytes_greater_than_4,
    remaining_bytes_jmp_offset_4,
];

pub fn bytes_len_less_than_8() -> Hint {
    Hint::new(
        String::from("bytes_len_less_than_8"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let bytes_len = get_integer_from_var_name("bytes_len", vm, _ids_data, _ap_tracking)?;
            let less_than_8 = Felt252::from(bytes_len < Felt252::from(8));
            insert_value_from_var_name("less_than_8", less_than_8, vm, _ids_data, _ap_tracking)?;
            Ok(())
        },
    )
}

pub fn bytes_len_less_than_4() -> Hint {
    Hint::new(
        String::from("bytes_len_less_than_4"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let bytes_len = get_integer_from_var_name("bytes_len", vm, _ids_data, _ap_tracking)?;
            let less_than_4 = Felt252::from(bytes_len < Felt252::from(4));
            insert_value_from_var_name("less_than_4", less_than_4, vm, _ids_data, _ap_tracking)?;
            Ok(())
        },
    )
}

pub fn remaining_bytes_greater_than_8() -> Hint {
    Hint::new(
        String::from("remaining_bytes_greater_than_8"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let bytes_len = get_integer_from_var_name("bytes_len", vm, _ids_data, _ap_tracking)?;
            let bytes8 = get_ptr_from_var_name("bytes8", vm, _ids_data, _ap_tracking)?;
            let fp = vm.get_fp();
            let dst = vm.get_relocatable((fp - 5)?)?;

            let processed_bytes_len = (bytes8 - dst)? * 8;
            let remaining_bytes_len = bytes_len - Felt252::from(processed_bytes_len);
            let continue_loop = Felt252::from(remaining_bytes_len >= Felt252::from(8));

            insert_value_from_var_name(
                "continue_loop",
                continue_loop,
                vm,
                _ids_data,
                _ap_tracking,
            )?;
            Ok(())
        },
    )
}

pub fn remaining_bytes_greater_than_4() -> Hint {
    Hint::new(
        String::from("remaining_bytes_greater_than_4"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let bytes_len = get_integer_from_var_name("bytes_len", vm, _ids_data, _ap_tracking)?;
            let bytes4 = get_ptr_from_var_name("bytes4", vm, _ids_data, _ap_tracking)?;
            let fp = vm.get_fp();
            let dst = vm.get_relocatable((fp - 5)?)?;

            let processed_bytes_len = (bytes4 - dst)? * 4;
            let remaining_bytes_len = bytes_len - Felt252::from(processed_bytes_len);
            let continue_loop = Felt252::from(remaining_bytes_len >= Felt252::from(4));

            insert_value_from_var_name(
                "continue_loop",
                continue_loop,
                vm,
                _ids_data,
                _ap_tracking,
            )?;
            Ok(())
        },
    )
}

pub fn remaining_bytes_jmp_offset() -> Hint {
    Hint::new(
        String::from("remaining_bytes_jmp_offset"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let bytes_len = get_integer_from_var_name("bytes_len", vm, _ids_data, _ap_tracking)?;
            let bytes8 = get_ptr_from_var_name("bytes8", vm, _ids_data, _ap_tracking)?;
            let fp = vm.get_fp();
            let dst = vm.get_relocatable((fp - 5)?)?;

            let processed_bytes_len = (bytes8 - dst)? * 8;
            let remaining_bytes_len = bytes_len - Felt252::from(processed_bytes_len);
            let remaining_offset = remaining_bytes_len * Felt252::from(2) + 1;

            insert_value_from_var_name(
                "remaining_offset",
                remaining_offset,
                vm,
                _ids_data,
                _ap_tracking,
            )?;
            Ok(())
        },
    )
}

pub fn remaining_bytes_jmp_offset_4() -> Hint {
    Hint::new(
        String::from("remaining_bytes_jmp_offset_4"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let bytes_len = get_integer_from_var_name("bytes_len", vm, _ids_data, _ap_tracking)?;
            let bytes4 = get_ptr_from_var_name("bytes4", vm, _ids_data, _ap_tracking)?;
            let fp = vm.get_fp();
            let dst = vm.get_relocatable((fp - 5)?)?;

            let processed_bytes_len = (bytes4 - dst)? * 4;
            let remaining_bytes_len = bytes_len - Felt252::from(processed_bytes_len);
            let remaining_offset = remaining_bytes_len * Felt252::from(2) + 1;

            insert_value_from_var_name(
                "remaining_offset",
                remaining_offset,
                vm,
                _ids_data,
                _ap_tracking,
            )?;
            Ok(())
        },
    )
}
