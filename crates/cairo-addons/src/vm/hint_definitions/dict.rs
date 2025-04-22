use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{
            get_integer_from_var_name, get_ptr_from_var_name, insert_value_from_var_name,
            insert_value_into_ap,
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
    attach_name,
    dict_new_empty,
    dict_squash,
    copy_tracker_to_new_ptr,
    merge_dict_tracker_with_parent,
    update_dict_tracker,
];

pub fn attach_name() -> Hint {
    Hint::new(
        String::from("attach_name"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let name_felt = get_integer_from_var_name("name", vm, ids_data, ap_tracking)?;
            let name_bytes = name_felt.to_bytes_be().to_vec();
            let name = String::from_utf8(name_bytes)
                .unwrap_or_else(|_| "invalid_name".to_string())
                .trim_matches(char::from(0))
                .to_string();
            let dict_ptr = get_ptr_from_var_name("dict_ptr", vm, ids_data, ap_tracking)?;
            let binding = exec_scopes.get_dict_manager()?;
            let mut binding = binding.borrow_mut();
            let tracker = binding.get_tracker_mut(dict_ptr)?;
            tracker.name = Some(name.clone());
            Ok(())
        },
    )
}
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
            let tracker = dict_manager.get_tracker_mut(dict_accesses_end)?;
            // Marks the tracker as squashed - so that after the end of a run, we can assert that
            // all dicts were properly squashed.
            tracker.is_squashed = true;
            let copied_data = tracker.get_dictionary_copy();
            let copied_default_value = tracker.get_default_value().cloned();

            let base = match copied_default_value {
                Some(default_value) => {
                    // Create a new default dict with the copied data
                    dict_manager.new_default_dict(vm, &default_value, Some(copied_data))?
                }
                None => {
                    // Create a new regular dict with the copied data
                    dict_manager.new_dict(vm, copied_data)?
                }
            };
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
            let tracker_name = tracker.name.clone().unwrap_or_default();
            let copied_data = tracker.get_dictionary_copy();
            let default_value = tracker.get_default_value().cloned();

            // Create new dict with copied data and insert its pointer
            match default_value {
                Some(default_value) => {
                    let new_dict_ptr =
                        dict_manager.new_default_dict(vm, &default_value, Some(copied_data))?;
                    let new_dict_tracker =
                        dict_manager.get_tracker_mut(new_dict_ptr.get_relocatable().unwrap())?;
                    new_dict_tracker.name = Some(format!("{}_copy", tracker_name));
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
                    let new_dict_tracker =
                        dict_manager.get_tracker_mut(new_dict_ptr.get_relocatable().unwrap())?;
                    new_dict_tracker.name = Some(format!("{}_copy", tracker_name));
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

            // If we're merging with the parent, it becomes the responsibility of the parent to
            // finalize the dict. We can thus consider it squashed.
            let current_tracker = dict_manager.get_tracker_mut(dict_ptr)?;
            current_tracker.is_squashed = true;
            let current_data = current_tracker.get_dictionary_copy();
            let parent_tracker = dict_manager.get_tracker_mut(parent_dict_end)?;
            parent_tracker.is_squashed = false;
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
