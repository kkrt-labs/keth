use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::{
            dict_manager::DictTracker,
            hint_utils::{get_ptr_from_var_name, insert_value_from_var_name, insert_value_into_ap},
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
    dict_new_empty,
    dict_squash,
    copy_tracker_to_new_ptr,
    merge_dict_tracker_with_parent,
    update_dict_tracker,
];

pub fn dict_new_empty() -> Hint {
    Hint::new(
        String::from("dict_new_empty"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let base =
                exec_scopes.get_dict_manager()?.borrow_mut().new_dict(vm, Default::default())?;
            insert_value_into_ap(vm, base)
        },
    )
}

pub fn dict_squash() -> Hint {
    Hint::new(
        String::from("dict_squash"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get the dict_accesses_end pointer
            let dict_accesses_end =
                get_ptr_from_var_name("dict_accesses_end", vm, ids_data, ap_tracking)?;

            // Get dict manager and copy data from the source dictionary
            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let mut dict_manager = dict_manager_ref.borrow_mut();
            let tracker = dict_manager.get_tracker(dict_accesses_end)?;
            let copied_data = tracker.get_dictionary_copy();

            // Create new dict with copied data
            let base = dict_manager.new_dict(vm, copied_data)?;

            // Insert the new dictionary's base pointer into ap
            insert_value_into_ap(vm, base)
        },
    )
}

pub fn copy_tracker_to_new_ptr() -> Hint {
    Hint::new(
        String::from("copy_tracker_to_new_ptr"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get original dict pointer
            let original_dict_ptr =
                get_ptr_from_var_name("parent_dict_end", vm, ids_data, ap_tracking)?;

            // Get tracker and copy its data
            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let mut dict_manager = dict_manager_ref.borrow_mut();
            let tracker = dict_manager.get_tracker(original_dict_ptr)?;
            let copied_data = tracker.get_dictionary_copy();
            let default_value = tracker.get_default_value().cloned();

            // Create new dict with copied data and insert its pointer
            match default_value {
                Some(default_value) => {
                    let new_dict_ptr =
                        dict_manager.new_default_dict(vm, &default_value, Some(copied_data))?;
                    insert_value_from_var_name(
                        "new_dict_ptr",
                        new_dict_ptr,
                        vm,
                        ids_data,
                        ap_tracking,
                    )
                }
                None => {
                    let new_dict_ptr = dict_manager.new_dict(vm, copied_data)?;
                    insert_value_from_var_name(
                        "new_dict_ptr",
                        new_dict_ptr,
                        vm,
                        ids_data,
                        ap_tracking,
                    )
                }
            }
        },
    )
}

pub fn merge_dict_tracker_with_parent() -> Hint {
    Hint::new(
        String::from("merge_dict_tracker_with_parent"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let dict_ptr = get_ptr_from_var_name("dict_ptr", vm, ids_data, ap_tracking)?;
            let parent_dict_end =
                get_ptr_from_var_name("parent_dict_end", vm, ids_data, ap_tracking)?;

            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let mut dict_manager = dict_manager_ref.borrow_mut();

            let current_data = dict_manager.get_tracker(dict_ptr)?.get_dictionary_copy();
            let parent_tracker = dict_manager.get_tracker_mut(parent_dict_end)?;
            for (key, value) in current_data {
                parent_tracker.insert_value(&key, &value);
            }

            Ok(())
        },
    )
}

pub fn update_dict_tracker() -> Hint {
    Hint::new(
        String::from("update_dict_tracker"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let current_tracker_ptr =
                get_ptr_from_var_name("current_tracker_ptr", vm, ids_data, ap_tracking)?;
            let new_tracker_ptr =
                get_ptr_from_var_name("new_tracker_ptr", vm, ids_data, ap_tracking)?;

            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let mut dict_manager = dict_manager_ref.borrow_mut();
            let tracker = dict_manager.get_tracker_mut(current_tracker_ptr)?;
            tracker.current_ptr = new_tracker_ptr;

            Ok(())
        },
    )
}
