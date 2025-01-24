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
    dict_copy,
    copy_dict_segment,
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

pub fn dict_copy() -> Hint {
    Hint::new(
        String::from("dict_copy"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get the new_start and dict_start pointers from ids
            let new_start = get_ptr_from_var_name("new_start", vm, ids_data, ap_tracking)?;
            let dict_start = get_ptr_from_var_name("dict_start", vm, ids_data, ap_tracking)?;
            let new_end = get_ptr_from_var_name("new_end", vm, ids_data, ap_tracking)?;

            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let mut dict_manager = dict_manager_ref.borrow_mut();

            // Check if new segment already exists in trackers
            // Get and copy data from the source dictionary
            let source_tracker = dict_manager.trackers.get(&dict_start.segment_index).ok_or(
                HintError::CustomHint(Box::from(format!(
                    "Segment {} already exists in dict_manager.trackers",
                    new_start.segment_index
                ))),
            )?;
            let copied_data = source_tracker.get_dictionary_copy();
            let default_value = source_tracker.get_default_value().cloned();

            // Create new tracker with copied data
            if let Some(default_value) = default_value {
                dict_manager.trackers.insert(
                    new_end.segment_index,
                    DictTracker::new_default_dict(new_end, &default_value, Some(copied_data)),
                );
            } else {
                dict_manager.trackers.insert(
                    new_end.segment_index,
                    DictTracker::new_with_initial(new_end, copied_data),
                );
            }

            Ok(())
        },
    )
}

pub fn copy_dict_segment() -> Hint {
    Hint::new(
        String::from("copy_dict_segment"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get original dict pointer
            let parent_dict_ptr = get_ptr_from_var_name("parent_dict", vm, ids_data, ap_tracking)?;
            let original_dict_ptr = vm.get_relocatable((parent_dict_ptr + 1)?)?;

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
