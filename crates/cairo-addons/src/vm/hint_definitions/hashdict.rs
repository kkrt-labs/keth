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
    types::{
        errors::math_errors::MathError, exec_scope::ExecutionScopes, relocatable::MaybeRelocatable,
    },
    vm::{
        errors::{hint_errors::HintError, memory_errors::MemoryError},
        vm_core::VirtualMachine,
    },
    Felt252,
};
use num_traits::Zero;
use starknet_crypto::poseidon_hash_many;

use crate::vm::hints::Hint;

pub const HINTS: &[fn() -> Hint] = &[
    hashdict_read,
    hashdict_write,
    hashdict_read_from_key,
    get_preimage_for_key,
    copy_hashdict_tracker_entry,
    get_storage_keys_for_address,
];

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
            let mut dict_manager = dict_manager_ref.borrow_mut();
            let tracker = dict_manager.get_tracker_mut(dict_ptr)?;
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
            })?;

            let hashed_key = compute_hash_key(&dict_key, key_len);
            dict_manager.preimages.insert(hashed_key.into(), dict_key);
            Ok(())
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
            let mut dict_manager = dict_manager_ref.borrow_mut();
            let tracker = dict_manager.get_tracker_mut(dict_ptr)?;
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
            tracker.get_value(&dict_key).cloned().and_then(|value| {
                vm.insert_value(dict_ptr_prev_value, value).map_err(|_| {
                    HintError::Memory(MemoryError::UnknownMemoryCell(Box::new(dict_ptr_prev_value)))
                })
            })?;
            tracker.insert_value(&dict_key, &new_value);

            let hashed_key = compute_hash_key(&dict_key, key_len);
            dict_manager.preimages.insert(hashed_key.into(), dict_key);
            Ok(())
        },
    )
}

/// Same as above but skips keys with value 0 (empty storage)
pub fn get_storage_keys_for_address() -> Hint {
    Hint::new(
        String::from("get_storage_keys_for_address"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get dictionary tracker
            let dict_ptr = get_ptr_from_var_name("dict_ptr", vm, ids_data, ap_tracking)?;
            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let dict = dict_manager_ref.borrow();
            let tracker = dict.get_tracker(dict_ptr)?;

            // Build prefix from memory
            let prefix_ptr = get_ptr_from_var_name("prefix", vm, ids_data, ap_tracking)?;
            let prefix_len_felt: Felt252 =
                get_integer_from_var_name("prefix_len", vm, ids_data, ap_tracking)?;
            let prefix_len: usize = prefix_len_felt
                .try_into()
                .map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(prefix_len_felt)))?;

            let prefix: Vec<MaybeRelocatable> = (0..prefix_len)
                .map(|i| {
                    let addr = (prefix_ptr + i)?;
                    vm.get_maybe(&addr).ok_or_else(|| {
                        HintError::Memory(MemoryError::UnknownMemoryCell(Box::new(addr)))
                    })
                })
                .collect::<Result<_, _>>()?;

            // Find matching preimages
            let matching_preimages: Vec<&Vec<MaybeRelocatable>> = tracker
                .get_dictionary_ref()
                .iter()
                .filter_map(|(key, value)| {
                    let DictKey::Compound(key_parts) = key else { return None };

                    // Check if key_parts has enough elements and matches the prefix
                    if key_parts.len() < prefix.len() || key_parts[..prefix.len()] != prefix[..] {
                        return None;
                    }

                    // Return None if value is zero integer (deleted storage)
                    match value.get_int() {
                        Some(value) if value == Zero::zero() => None,
                        _ => Some(key_parts),
                    }
                })
                .collect();

            // Allocate memory segments and write results
            let base = vm.add_memory_segment();
            for (i, preimage) in matching_preimages.iter().enumerate() {
                let ptr = vm.add_memory_segment();
                let bytes32_base = vm.add_memory_segment();

                // Write the rest of preimage (excluding first element) to bytes32_base
                for (j, value) in preimage[1..].iter().enumerate() {
                    vm.insert_value((bytes32_base + j)?, value.clone())?;
                }

                // Write [first_element, bytes32_base] to ptr
                vm.insert_value(ptr, preimage[0].clone())?;
                vm.insert_value((ptr + 1)?, MaybeRelocatable::from(bytes32_base))?;

                // Write ptr to base[i]
                vm.insert_value((base + i)?, MaybeRelocatable::from(ptr))?;
            }

            // Set output values
            insert_value_from_var_name(
                "keys_len",
                Felt252::from(matching_preimages.len()),
                vm,
                ids_data,
                ap_tracking,
            )?;
            insert_value_from_var_name(
                "keys",
                MaybeRelocatable::from(base),
                vm,
                ids_data,
                ap_tracking,
            )?;

            Ok(())
        },
    )
}

pub fn hashdict_read_from_key() -> Hint {
    Hint::new(
        String::from("hashdict_read_from_key"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get the hashed key value
            let hashed_key = get_integer_from_var_name("key", vm, ids_data, ap_tracking)?;

            // Get dictionary tracker
            let dict_ptr = get_ptr_from_var_name("dict_ptr_stop", vm, ids_data, ap_tracking)?;
            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let mut dict_manager = dict_manager_ref.borrow_mut();
            let preimages = &dict_manager.preimages.clone();
            let tracker = dict_manager.get_tracker_mut(dict_ptr)?;

            // Find matching preimage and get its value. This hint can also be called on non-hashed
            // keys.
            let simple_key = DictKey::Simple(hashed_key.into());
            let preimage = _get_preimage_for_hashed_key(hashed_key.into(), preimages)
                .unwrap_or(&simple_key)
                .clone();
            let value = tracker
                .get_value(&preimage)
                .map_err(|_| {
                    HintError::CustomHint(
                        format!("No value found for preimage {}", preimage).into(),
                    )
                })?
                .clone();

            // Set the value
            insert_value_from_var_name("value", value, vm, ids_data, ap_tracking)
        },
    )
}

pub fn get_preimage_for_key() -> Hint {
    Hint::new(
        String::from("get_preimage_for_key"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get the hashed key value
            let hashed_key = get_integer_from_var_name("key", vm, ids_data, ap_tracking)?;

            // Get dictionary tracker
            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let dict_manager = dict_manager_ref.borrow();
            let preimages = &dict_manager.preimages;

            // Find matching preimage
            let preimage = _get_preimage_for_hashed_key(hashed_key.into(), preimages)?;

            // Write preimage data to memory
            let preimage_data_ptr =
                get_ptr_from_var_name("preimage_data", vm, ids_data, ap_tracking)?;
            if let DictKey::Compound(values) = preimage {
                for (i, value) in values.iter().enumerate() {
                    vm.insert_value((preimage_data_ptr + i)?, value.clone())?;
                }

                // Set preimage length
                insert_value_from_var_name(
                    "preimage_len",
                    Felt252::from(values.len()),
                    vm,
                    ids_data,
                    ap_tracking,
                )?;
            }

            Ok(())
        },
    )
}

pub fn copy_hashdict_tracker_entry() -> Hint {
    Hint::new(
        String::from("copy_hashdict_tracker_entry"),
        |vm: &mut VirtualMachine,
         exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let source_ptr_stop =
                get_ptr_from_var_name("source_ptr_stop", vm, ids_data, ap_tracking)?;
            let dest_ptr = get_ptr_from_var_name("dest_ptr", vm, ids_data, ap_tracking)?;
            let dict_manager_ref = exec_scopes.get_dict_manager()?;
            let mut dict_manager = dict_manager_ref.borrow_mut();
            let preimages = &dict_manager.preimages.clone();

            let source_tracker = dict_manager.get_tracker_mut(source_ptr_stop)?;

            // Find matching preimage from source tracker data
            let key_hash = get_integer_from_var_name("source_key", vm, ids_data, ap_tracking)?;
            let preimage = _get_preimage_for_hashed_key(key_hash.into(), preimages)?.clone();

            // The default behavior of `get_value` is to mark the tracker as unsquashed, as we're
            // accessing an internal value. However, in this specific case, we're not
            // mutating the dict access segment - so we want to retain the squashed state.
            let currently_squashed = source_tracker.is_squashed;
            let value = source_tracker
                .get_value(&preimage)
                .map_err(|_| {
                    HintError::CustomHint(
                        format!("No value found for preimage {}", preimage).into(),
                    )
                })?
                .clone();
            source_tracker.is_squashed = currently_squashed;

            // Update destination tracker
            let dest_tracker = dict_manager.get_tracker_mut(dest_ptr)?;
            dest_tracker.current_ptr.offset += DICT_ACCESS_SIZE;
            dest_tracker.insert_value(&preimage, &value.clone());

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

/// Helper function to find a preimage in a tracker's dictionary given a hashed key
fn _get_preimage_for_hashed_key(
    hashed_key: MaybeRelocatable,
    preimages: &HashMap<MaybeRelocatable, DictKey>,
) -> Result<&DictKey, HintError> {
    preimages.get(&hashed_key).ok_or_else(|| {
        HintError::CustomHint(format!("No preimage found for hashed key {}", hashed_key).into())
    })
}

/// Helper function to compute the hash key from a DictKey
fn compute_hash_key(dict_key: &DictKey, key_len: usize) -> Felt252 {
    if key_len != 1 {
        match dict_key {
            DictKey::Compound(values) => {
                let ints: Vec<Felt252> = values.iter().map(|v| v.get_int().unwrap()).collect();
                poseidon_hash_many(&ints)
            }
            DictKey::Simple(_) => panic!("Unreachable"),
        }
    } else {
        match dict_key {
            DictKey::Compound(values) => values[0].get_int().unwrap(),
            DictKey::Simple(value) => value.get_int().unwrap(),
        }
    }
}
