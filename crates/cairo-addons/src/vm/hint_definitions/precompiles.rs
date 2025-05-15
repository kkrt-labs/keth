use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{
            get_integer_from_var_name, insert_value_from_var_name,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};

use crate::vm::hints::Hint;

pub const HINTS: &[fn() -> Hint] = &[bit_length_hint, bytes_length_hint];

pub fn bit_length_hint() -> Hint {
    Hint::new(
        String::from("bit_length_hint"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let value = get_integer_from_var_name("value", vm, ids_data, ap_tracking)?;
            let bit_length = value.bits();

            insert_value_from_var_name("bit_length", bit_length, vm, ids_data, ap_tracking)
        },
    )
}

pub fn bytes_length_hint() -> Hint {
    Hint::new(
        String::from("bytes_length_hint"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let value = get_integer_from_var_name("value", vm, ids_data, ap_tracking)?;
            let bytes_length = value.bits().div_ceil(8);

            insert_value_from_var_name(
                "bytes_length",
                Felt252::from(bytes_length),
                vm,
                ids_data,
                ap_tracking,
            )
        },
    )
}
