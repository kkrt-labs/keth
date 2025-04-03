use ark_bls12_381::Fq as BlsFq;
use ark_bn254::{Fq as AltBnFq, Fq2 as AltBnFq2};
use ark_ff::Field;
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

use crate::vm::{hint_utils::Uint384, hints::Hint};

pub const HINTS: &[fn() -> Hint] =
    &[bnf_multiplicative_inverse, bnf2_multiplicative_inverse, blsf_multiplicative_inverse];

pub fn bnf_multiplicative_inverse() -> Hint {
    Hint::new(
        String::from("bnf_multiplicative_inverse"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let b_addr = get_ptr_from_var_name("b", vm, ids_data, ap_tracking)?;
            let c0_addr = vm.get_relocatable(b_addr)?;
            let c0 = Uint384::from_base_addr(c0_addr, "b.c0", vm)?.pack();

            let b = AltBnFq::from(c0);
            let b_inv = b.inverse().unwrap_or_default();

            let c0_u384 = Uint384::split(&b_inv.into());

            let bnf_struct_ptr = vm.add_memory_segment();
            let c0_ptr = vm.add_memory_segment();

            for i in 0..4 {
                vm.insert_value((c0_ptr + i)?, c0_u384.limbs[i].clone().into_owned())?;
            }
            vm.insert_value(bnf_struct_ptr, c0_ptr)?;
            insert_value_from_var_name("b_inv", bnf_struct_ptr, vm, ids_data, ap_tracking)?;
            Ok(())
        },
    )
}

pub fn bnf2_multiplicative_inverse() -> Hint {
    Hint::new(
        String::from("bnf2_multiplicative_inverse"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let b_addr = get_ptr_from_var_name("b", vm, ids_data, ap_tracking)?;
            let c0_addr = vm.get_relocatable(b_addr)?;
            let c1_addr = vm.get_relocatable((b_addr + 1_usize).unwrap())?;
            let c0 = Uint384::from_base_addr(c0_addr, "b.c0", vm)?.pack();
            let c1 = Uint384::from_base_addr(c1_addr, "b.c1", vm)?.pack();

            let b = AltBnFq2::new(c0.into(), c1.into());
            let b_inv = b.inverse().unwrap_or_default();

            let c0_u384 = Uint384::split(&b_inv.c0.into());
            let c1_u384 = Uint384::split(&b_inv.c1.into());

            let bnf2_struct_ptr = vm.add_memory_segment();
            let c0_ptr = vm.add_memory_segment();
            let c1_ptr = vm.add_memory_segment();

            for i in 0..4 {
                vm.insert_value((c0_ptr + i)?, c0_u384.limbs[i].clone().into_owned())?;
                vm.insert_value((c1_ptr + i)?, c1_u384.limbs[i].clone().into_owned())?;
            }
            vm.insert_value(bnf2_struct_ptr, c0_ptr)?;
            vm.insert_value((bnf2_struct_ptr + 1_usize).unwrap(), c1_ptr)?;
            insert_value_from_var_name("b_inv", bnf2_struct_ptr, vm, ids_data, ap_tracking)?;
            Ok(())
        },
    )
}

pub fn blsf_multiplicative_inverse() -> Hint {
    Hint::new(
        String::from("bnf_multiplicative_inverse"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let b_addr = get_ptr_from_var_name("b", vm, ids_data, ap_tracking)?;
            let c0_addr = vm.get_relocatable(b_addr)?;
            let c0 = Uint384::from_base_addr(c0_addr, "b.c0", vm)?.pack();

            let b = BlsFq::from(c0);
            let b_inv = b.inverse().unwrap_or_default();

            let c0_u384 = Uint384::split(&b_inv.into());

            let bnf_struct_ptr = vm.add_memory_segment();
            let c0_ptr = vm.add_memory_segment();

            for i in 0..4 {
                vm.insert_value((c0_ptr + i)?, c0_u384.limbs[i].clone().into_owned())?;
            }
            vm.insert_value(bnf_struct_ptr, c0_ptr)?;
            insert_value_from_var_name("b_inv", bnf_struct_ptr, vm, ids_data, ap_tracking)?;
            Ok(())
        },
    )
}
