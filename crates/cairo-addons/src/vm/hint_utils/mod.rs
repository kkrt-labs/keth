use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::get_ptr_from_var_name,
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::{
        errors::math_errors::MathError,
        relocatable::{MaybeRelocatable, Relocatable},
    },
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};

use std::collections::HashMap;
pub fn serialize_sequence(
    name: &str,
    vm: &mut VirtualMachine,
    ids_data: &HashMap<String, HintReference>,
    ap_tracking: &ApTracking,
) -> Result<Vec<Felt252>, HintError> {
    let ptr = get_ptr_from_var_name(name, vm, ids_data, ap_tracking)?;
    let len_addr = (ptr + 1)?;

    let len_felt = vm.get_integer(len_addr)?.into_owned();
    let len =
        len_felt.try_into().map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(len_felt)))?;

    let data = vm.get_relocatable(ptr)?;

    let mut bytes = Vec::new();
    for i in 0..len {
        let byte_addr = (data + i)?;
        let byte = vm.get_integer(byte_addr)?.into_owned();
        bytes.push(byte);
    }

    Ok(bytes)
}

pub fn deserialize_sequence<T>(
    sequence: Vec<T>,
    vm: &mut VirtualMachine,
) -> Result<Relocatable, HintError>
where
    Felt252: From<T>,
    T: Copy,
    T: std::fmt::Debug,
{
    // Allocate memory segments and write results
    let base = vm.add_memory_segment();
    let data_ptr = vm.add_memory_segment();
    let len = sequence.len();

    // Convert values and write to memory
    let relocatable_values = sequence
        .iter()
        .map(|value| MaybeRelocatable::Int((*value).into()))
        .collect::<Vec<MaybeRelocatable>>();

    vm.segments.write_arg(data_ptr, &relocatable_values)?;
    vm.segments.write_arg(
        base,
        &vec![MaybeRelocatable::from(data_ptr), MaybeRelocatable::Int(len.into())],
    )?;
    Ok(base)
}
