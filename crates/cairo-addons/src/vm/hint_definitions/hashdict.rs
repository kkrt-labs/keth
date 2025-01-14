use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::{
            dict_hint_utils::DICT_ACCESS_SIZE,
            dict_manager::DictKey,
            hint_utils::{
                get_integer_from_var_name, get_maybe_relocatable_from_var_name,
                get_ptr_from_var_name, insert_value_from_var_name,
            },
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::{errors::math_errors::MathError,relocatable::MaybeRelocatable, exec_scope::ExecutionScopes},
    vm::{
        errors::{hint_errors::HintError, memory_errors::MemoryError},
        vm_core::VirtualMachine,
    },
    Felt252,
};

use crate::vm::hints::Hint;

pub fn hashdict_read() -> Hint {
    Hint::new(
        String::from("hashdict_read"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get dictionary pointer and setup tracker
            let dict_ptr = get_ptr_from_var_name("dict_ptr", vm, ids_data, ap_tracking)?;
            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let mut dict = dict_manager_ref.borrow_mut();
            let tracker = dict.get_tracker_mut(dict_ptr)?;
            tracker.current_ptr.offset += DICT_ACCESS_SIZE;

            let key = get_ptr_from_var_name("key", vm, ids_data, ap_tracking)?;
            let key_len_felt: Felt252 =
                get_integer_from_var_name("key_len", vm, ids_data, ap_tracking)?;
            let key_len: usize = key_len_felt
                .try_into()
                .map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(key_len_felt)))?;

            // Build and process compound key
            let dict_key = build_compound_key(vm, &key, key_len)?;
            tracker.get_value(&dict_key).and_then(|value| {
                insert_value_from_var_name("value", value.clone(), vm, ids_data, ap_tracking)
            })
        },
    )
}

pub fn hashdict_write() -> Hint {
    Hint::new(
        String::from("hashdict_write"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get dictionary pointer and setup tracker
            let dict_ptr = get_ptr_from_var_name("dict_ptr", vm, ids_data, ap_tracking)?;
            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let mut dict = dict_manager_ref.borrow_mut();
            let tracker = dict.get_tracker_mut(dict_ptr)?;
            tracker.current_ptr.offset += DICT_ACCESS_SIZE;

            let key = get_ptr_from_var_name("key", vm, ids_data, ap_tracking)?;
            let key_len_felt: Felt252 =
                get_integer_from_var_name("key_len", vm, ids_data, ap_tracking)?;
            let key_len: usize = key_len_felt
                .try_into()
                .map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(key_len_felt)))?;

            // Build compound key and get new value
            let dict_key = build_compound_key(vm, &key, key_len)?;
            let new_value =
                get_maybe_relocatable_from_var_name("new_value", vm, ids_data, ap_tracking)?;
            let dict_ptr_prev_value = (dict_ptr + 1_i32)?;

            // Update tracker and memory
            let tracker_dict = tracker.get_dictionary_ref();
            let prev_value = tracker_dict.get(&dict_key).cloned().unwrap_or(MaybeRelocatable::Int(0.into()));
            tracker.insert_value(&dict_key, &new_value);
            vm.insert_value(dict_ptr_prev_value, prev_value)?;

            Ok(())
        },
    )
}

fn build_compound_key(
    vm: &VirtualMachine,
    key: &cairo_vm::types::relocatable::Relocatable,
    key_len: usize,
) -> Result<DictKey, HintError> {
    (0..key_len)
        .map(|i| {
            let mem_addr = (*key + i)?;
            vm.get_maybe(&mem_addr).ok_or_else(|| {
                HintError::Memory(MemoryError::UnknownMemoryCell(Box::from(mem_addr)))
            })
        })
        .collect::<Result<Vec<_>, _>>()
        .map(DictKey::Compound)
}
