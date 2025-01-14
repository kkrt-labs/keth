use std::{cell::RefCell, collections::HashMap, rc::Rc};

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::{
            dict_manager::DictManager,
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

pub fn dict_new_empty() -> Hint {
    Hint::new(
        String::from("dict_new_empty"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            //Check if there is a dict manager in scope, create it if there isnt one
            let base = if let Ok(dict_manager) = exec_scopes.get_dict_manager() {
                dict_manager.borrow_mut().new_dict(vm, Default::default())?
            } else {
                let mut dict_manager = DictManager::new();
                let base = dict_manager.new_dict(vm, Default::default())?;
                exec_scopes.insert_value("dict_manager", Rc::new(RefCell::new(dict_manager)));
                base
            };
            insert_value_into_ap(vm, base)
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
            let original_mapping_ptr =
                get_ptr_from_var_name("original_mapping", vm, ids_data, ap_tracking)?;
            let original_dict_ptr = vm.get_relocatable((original_mapping_ptr + 1)?)?;

            // Get tracker and copy its data
            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let mut dict_manager = dict_manager_ref.borrow_mut();
            let tracker = dict_manager.get_tracker(original_dict_ptr)?;
            let copied_data = tracker.get_dictionary_copy();

            // Create new dict with copied data and insert its pointer
            let new_dict_ptr = dict_manager.new_dict(vm, copied_data)?;
            insert_value_from_var_name("new_dict_ptr", new_dict_ptr, vm, ids_data, ap_tracking)
        },
    )
}
