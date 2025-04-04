use crate::vm::{
    hint_utils::{deserialize_sequence, serialize_sequence},
    hints::Hint,
};
use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::insert_value_from_var_name,
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use nybbles::{common_prefix_length, Nibbles};
use std::collections::HashMap;

pub const HINTS: &[fn() -> Hint] = &[common_prefix_length_hint, bytes_to_nibble_list_hint];

pub fn common_prefix_length_hint() -> Hint {
    Hint::new(
        String::from("common_prefix_length_hint"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let a_bytes = serialize_sequence("a", vm, ids_data, ap_tracking)?
                .into_iter()
                .map(|b| b.try_into().unwrap())
                .collect::<Vec<u8>>();
            let b_bytes = serialize_sequence("b", vm, ids_data, ap_tracking)?
                .into_iter()
                .map(|b| b.try_into().unwrap())
                .collect::<Vec<u8>>();

            let common_len = common_prefix_length(&a_bytes, &b_bytes);

            insert_value_from_var_name(
                "result",
                Felt252::from(common_len),
                vm,
                ids_data,
                ap_tracking,
            )
        },
    )
}

pub fn bytes_to_nibble_list_hint() -> Hint {
    Hint::new(
        String::from("bytes_to_nibble_list_hint"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let bytes_ = serialize_sequence("bytes_", vm, ids_data, ap_tracking)?
                .into_iter()
                .map(|b| b.try_into().unwrap())
                .collect::<Vec<u8>>();
            let nibble_list = Nibbles::unpack(bytes_.as_slice());

            let base = deserialize_sequence(nibble_list.to_vec(), vm)?;
            insert_value_from_var_name("result", base, vm, ids_data, ap_tracking)
        },
    )
}
