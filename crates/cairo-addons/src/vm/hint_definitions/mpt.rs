use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{get_ptr_from_var_name, insert_value_from_var_name},
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};

use crate::vm::hints::Hint;

pub const HINTS: &[fn() -> Hint] = &[find_two_non_null_subnodes];

pub fn find_two_non_null_subnodes() -> Hint {
    Hint::new(
        String::from("find_two_non_null_subnodes"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get `subnodes_ptr` from ids
            let subnodes_ptr = get_ptr_from_var_name("subnodes_ptr", vm, ids_data, ap_tracking)?;

            let mut non_null_indices: Vec<Felt252> = Vec::new();

            // Check each of the 16 possible indices (0-15)
            for idx in 0..16u32 {
                // Get the pointer to the subnode at this index
                let subnode_ptr_addr = (subnodes_ptr + idx)?;
                let maybe_subnode_ptr_value = vm.get_maybe(&subnode_ptr_addr);

                if let Some(subnode_ptr) = maybe_subnode_ptr_value {
                    // Check if this is a non-null subnode by verifying the inner structure

                    // Subnode pointer MUST be a relocatable, we can unwrap safely
                    let inner_ptr_addr = subnode_ptr.get_relocatable().unwrap();

                    // Case 1: subnode is a digest
                    // Inner pointer is an ExtendedEnum, with 7 fields, we can offset by 2 to get
                    // the bytes pointer and unwrap safely
                    if let Some(bytes_ptr) = vm.get_maybe(&(inner_ptr_addr + 2u32).unwrap()) {
                        // If bytes_ptr is the Zero value instead of a relocatable, then the subnode
                        // is either null or an embedded node
                        if let Some(bytes_ptr) = bytes_ptr.get_relocatable() {
                            // Well formed BytesStruct has 2 fields, we can offset by 1 to get the
                            // length
                            let bytes_len = vm.get_maybe(&(bytes_ptr + 1u32).unwrap()).unwrap();

                            // If the value is not 0, this SHOULD be a non-null subnode
                            // As we construct non-null bytes with length > 0
                            if bytes_len.get_int().unwrap() != Felt252::ZERO {
                                non_null_indices.push(idx.into());

                                // If we found 2 non-null subnodes, we can stop
                                if non_null_indices.len() >= 2 {
                                    break;
                                }
                            }
                        }
                    }

                    // Case 2: subnode is an embedded node
                    // Inner pointer is an ExtendedEnum, with 7 fields, we can offset by 0 to get
                    // the sequence pointer and unwrap safely
                    if let Some(sequence_ptr) = vm.get_maybe(&inner_ptr_addr) {
                        // If sequence_ptr is the Zero value instead of a relocatable, then the
                        // subnode is either null or an embedded node
                        if let Some(sequence_ptr) = sequence_ptr.get_relocatable() {
                            // Well formed SequenceExtendedStruct has 2 fields, we can offset by 1
                            // to get the length
                            let sequence_len =
                                vm.get_maybe(&(sequence_ptr + 1u32).unwrap()).unwrap();

                            // If the value is not 0, this SHOULD be a non-null subnode
                            // As we construct non-null sequences with length > 0
                            if sequence_len.get_int().unwrap() != Felt252::ZERO {
                                non_null_indices.push(idx.into());

                                // If we found 2 non-null subnodes, we can stop
                                if non_null_indices.len() >= 2 {
                                    break;
                                }
                            }
                        }
                    }
                }
            }

            // Insert the found indices into the VM
            if non_null_indices.len() >= 2 {
                insert_value_from_var_name(
                    "first_non_null_index",
                    non_null_indices[0],
                    vm,
                    ids_data,
                    ap_tracking,
                )?;

                insert_value_from_var_name(
                    "second_non_null_index",
                    non_null_indices[1],
                    vm,
                    ids_data,
                    ap_tracking,
                )?;

                Ok(())
            } else {
                Err(HintError::CustomHint(Box::from(format!(
                    "Could not find two non-null subnodes. Found only {}",
                    non_null_indices.len()
                ))))
            }
        },
    )
}
