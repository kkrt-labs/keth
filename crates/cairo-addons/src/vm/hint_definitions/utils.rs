use lazy_static::lazy_static;
use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::{
            dict_manager::DictTracker,
            hint_utils::{
                get_integer_from_var_name, get_maybe_relocatable_from_var_name,
                get_ptr_from_var_name, insert_value_from_var_name, insert_value_into_ap,
            },
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::{
        errors::math_errors::MathError, exec_scope::ExecutionScopes, relocatable::MaybeRelocatable,
    },
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};

use crate::vm::{hint_utils::serialize_sequence, hints::Hint};
use revm_precompile::{
    blake2, bn128, hash, identity, kzg_point_evaluation, modexp, secp256k1, Address,
};

pub const HINTS: &[fn() -> Hint] = &[
    bytes__eq__,
    b_le_a,
    fp_plus_2_or_0,
    nibble_remainder,
    print_maybe_relocatable,
    precompile_index_from_address,
    initialize_jumpdests,
];

lazy_static! {
    static ref PRECOMPILE_INDICES: HashMap<Address, Felt252> = {
        let mut map = HashMap::new();
        // Using the imported precompiles, multiply index by 3 as per previous logic
        map.insert(secp256k1::ECRECOVER.0, Felt252::from(0));     // index 0
        map.insert(hash::SHA256.0, Felt252::from(3));             // index 1
        map.insert(hash::RIPEMD160.0, Felt252::from(2 * 3));          // index 2
        map.insert(identity::FUN.0, Felt252::from(3 * 3));       // index 3
        map.insert(modexp::BYZANTIUM.0, Felt252::from(4 * 3));          // index 4
        map.insert(bn128::add::BYZANTIUM.0, Felt252::from(5 * 3));              // index 5
        map.insert(bn128::mul::BYZANTIUM.0, Felt252::from(6 * 3));              // index 6
        map.insert(bn128::pair::ADDRESS, Felt252::from(7 * 3));          // index 7
        map.insert(blake2::FUN.0, Felt252::from(8 * 3));         // index 8
        map.insert(kzg_point_evaluation::ADDRESS, Felt252::from(9 * 3));    // index 10
        map
    };
}

#[allow(non_snake_case)]
pub fn bytes__eq__() -> Hint {
    Hint::new(
        String::from("Bytes__eq__"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let self_bytes = serialize_sequence("_self", vm, ids_data, ap_tracking)?;
            let other_bytes = serialize_sequence("other", vm, ids_data, ap_tracking)?;

            for i in 0..std::cmp::min(self_bytes.len(), other_bytes.len()) {
                if self_bytes[i] != other_bytes[i] {
                    insert_value_from_var_name(
                        "is_diff",
                        MaybeRelocatable::from(1),
                        vm,
                        ids_data,
                        ap_tracking,
                    )?;
                    insert_value_from_var_name(
                        "diff_index",
                        MaybeRelocatable::from(i),
                        vm,
                        ids_data,
                        ap_tracking,
                    )?;
                    return Ok(());
                }
            }

            // No differences found in common prefix
            // Lengths were checked before this hint
            insert_value_from_var_name(
                "is_diff",
                MaybeRelocatable::from(0),
                vm,
                ids_data,
                ap_tracking,
            )?;
            insert_value_from_var_name(
                "diff_index",
                MaybeRelocatable::from(0),
                vm,
                ids_data,
                ap_tracking,
            )?;
            Ok(())
        },
    )
}

pub fn b_le_a() -> Hint {
    Hint::new(
        String::from("b_le_a"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let a = get_integer_from_var_name("a", vm, ids_data, ap_tracking)?;
            let b = get_integer_from_var_name("b", vm, ids_data, ap_tracking)?;
            let result = usize::from(b <= a);
            insert_value_from_var_name(
                "is_min_b",
                MaybeRelocatable::from(result),
                vm,
                ids_data,
                ap_tracking,
            )?;
            Ok(())
        },
    )
}

pub fn fp_plus_2_or_0() -> Hint {
    Hint::new(
        String::from("fp_plus_2_or_0"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let fp_offset = (vm.get_fp() + 2)?;
            let value_set = vm.get_maybe(&fp_offset);
            if value_set.is_none() {
                vm.insert_value(fp_offset, MaybeRelocatable::from(0))?;
            }
            Ok(())
        },
    )
}

pub fn nibble_remainder() -> Hint {
    Hint::new(
        String::from("memory[fp + 2] = to_felt_or_relocatable(ids.x.value.len % 2)"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let bytes_ptr = get_ptr_from_var_name("x", vm, ids_data, ap_tracking)?;
            let len = vm.get_integer((bytes_ptr + 1)?)?.into_owned();
            let len: usize =
                len.try_into().map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(len)))?;
            let remainder = len % 2;
            vm.insert_value((vm.get_fp() + 2)?, MaybeRelocatable::from(remainder))?;
            Ok(())
        },
    )
}

pub fn print_maybe_relocatable() -> Hint {
    Hint::new(
        String::from("print_maybe_relocatable"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let maybe_relocatable =
                get_maybe_relocatable_from_var_name("x", vm, ids_data, ap_tracking)?;
            println!("maybe_relocatable: {:?}", maybe_relocatable);
            Ok(())
        },
    )
}

pub fn precompile_index_from_address() -> Hint {
    Hint::new(
        String::from("precompile_index_from_address"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let address_felt = get_integer_from_var_name("address", vm, ids_data, ap_tracking)?;

            let address = Address::from({
                let bytes = address_felt.to_bytes_le();
                let mut address_bytes = [0u8; 20];
                address_bytes.copy_from_slice(&bytes[..20]);
                address_bytes
            });

            let index = PRECOMPILE_INDICES.get(&address).ok_or(HintError::CustomHint(
                Box::from(format!("Invalid precompile address: {:?}", address)),
            ))?;

            insert_value_from_var_name(
                "index",
                MaybeRelocatable::from(*index),
                vm,
                ids_data,
                ap_tracking,
            )?;
            Ok(())
        },
    )
}

pub fn initialize_jumpdests() -> Hint {
    Hint::new(
        String::from("initialize_jumpdests"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Get bytecode pointer and length
            let bytecode =
                get_maybe_relocatable_from_var_name("bytecode", vm, ids_data, ap_tracking)?;
            let bytecode_ptr = match bytecode {
                MaybeRelocatable::RelocatableValue(ptr) => ptr,
                MaybeRelocatable::Int(value) if value == Felt252::ZERO => {
                    // Handle empty bytecode case
                    let base = vm.add_memory_segment();

                    // Get dict manager and create empty dictionary
                    let dict_manager_ref = _exec_scopes.get_dict_manager()?;
                    let mut dict_manager = dict_manager_ref.borrow_mut();

                    // Create and insert empty DictTracker
                    dict_manager.trackers.insert(
                        base.segment_index,
                        DictTracker::new_default_dict(
                            base,
                            &MaybeRelocatable::from(Felt252::ZERO),
                            Some(HashMap::new()),
                        ),
                    );

                    // Store base address in ap and return
                    insert_value_into_ap(vm, base)?;
                    return Ok(());
                }
                _ => return Err(HintError::CustomHint(Box::from("Invalid bytecode value"))),
            };

            let bytecode_len =
                get_integer_from_var_name("bytecode_len", vm, ids_data, ap_tracking)?;
            let len: usize = bytecode_len
                .try_into()
                .map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(bytecode_len)))?;

            // Read bytecode from memory
            let mut bytecode = Vec::with_capacity(len);
            for i in 0..len {
                let value = vm.get_integer((bytecode_ptr + i)?)?.into_owned();
                bytecode.push(value.to_bytes_be()[31]); // Get least significant byte
            }

            // Get valid jump destinations
            let valid_jumpdest = get_valid_jump_destinations(&bytecode);

            // Create dictionary data with valid jump destinations
            let mut data = HashMap::new();
            for dest in valid_jumpdest {
                data.insert(Felt252::from(dest).into(), Felt252::ONE.into());
            }

            // Create new segment for the dictionary
            let base = vm.add_memory_segment();

            // Get dict manager and verify segment doesn't exist
            let dict_manager_ref = _exec_scopes.get_dict_manager()?;
            let mut dict_manager = dict_manager_ref.borrow_mut();
            if dict_manager.trackers.contains_key(&base.segment_index) {
                return Err(HintError::CustomHint(Box::from(
                    "Segment already exists in dict_manager.trackers",
                )));
            }

            // Create and insert DictTracker
            dict_manager.trackers.insert(
                base.segment_index,
                DictTracker::new_default_dict(
                    base,
                    &MaybeRelocatable::from(Felt252::ZERO),
                    Some(data),
                ),
            );

            // Store base address in ap
            insert_value_into_ap(vm, base)?;

            Ok(())
        },
    )
}

fn get_valid_jump_destinations(code: &[u8]) -> Vec<usize> {
    let mut valid_jumpdest = Vec::new();
    let mut i = 0;

    while i < code.len() {
        if code[i] == 0x5b {
            // JUMPDEST opcode
            valid_jumpdest.push(i);
            i += 1;
            continue;
        }

        // Skip push data
        if code[i] >= 0x60 && code[i] <= 0x7f {
            let n = (code[i] - 0x60 + 1) as usize;
            i += n + 1;
            continue;
        }

        i += 1;
    }

    valid_jumpdest
}
