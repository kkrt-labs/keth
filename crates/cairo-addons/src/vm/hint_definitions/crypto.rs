use ark_bls12_381::{Fq as BlsFq, Fq2 as BlsFq2};
use ark_bn254::{Fq as AltBnFq, Fq2 as AltBnFq2};
use ark_ff::Field;
use num_bigint::BigUint;
use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{get_ptr_from_var_name, insert_value_from_var_name},
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::{exec_scope::ExecutionScopes, relocatable::Relocatable},
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};

use crate::vm::{hint_utils::Uint384, hints::Hint};

pub const HINTS: &[fn() -> Hint] = &[
    bnf_multiplicative_inverse,
    bnf2_multiplicative_inverse,
    blsf_multiplicative_inverse,
    blsf2_multiplicative_inverse,
];

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
            insert_field_element_from_var_name::<1>(
                "b_inv",
                &[c0_u384],
                vm,
                ids_data,
                ap_tracking,
            )?;
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
            let (c0, c1) = extract_quadratic_field_element_from_base(b_addr, vm)?;

            let b = AltBnFq2::new(c0.into(), c1.into());
            let b_inv = b.inverse().unwrap_or_default();

            let c0_u384 = Uint384::split(&b_inv.c0.into());
            let c1_u384 = Uint384::split(&b_inv.c1.into());

            insert_field_element_from_var_name::<2>(
                "b_inv",
                &[c0_u384, c1_u384],
                vm,
                ids_data,
                ap_tracking,
            )?;
            Ok(())
        },
    )
}

pub fn blsf_multiplicative_inverse() -> Hint {
    Hint::new(
        String::from("blsf_multiplicative_inverse"),
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
            insert_field_element_from_var_name::<1>(
                "b_inv",
                &[c0_u384],
                vm,
                ids_data,
                ap_tracking,
            )?;
            Ok(())
        },
    )
}

pub fn blsf2_multiplicative_inverse() -> Hint {
    Hint::new(
        String::from("blsf2_multiplicative_inverse"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let b_addr = get_ptr_from_var_name("b", vm, ids_data, ap_tracking)?;
            let (c0, c1) = extract_quadratic_field_element_from_base(b_addr, vm)?;

            let b = BlsFq2::new(c0.into(), c1.into());
            let b_inv = b.inverse().unwrap_or_default();
            let c0_u384 = Uint384::split(&b_inv.c0.into());
            let c1_u384 = Uint384::split(&b_inv.c1.into());

            insert_field_element_from_var_name::<2>(
                "b_inv",
                &[c0_u384, c1_u384],
                vm,
                ids_data,
                ap_tracking,
            )?;
            Ok(())
        },
    )
}

fn extract_quadratic_field_element_from_base(
    base: Relocatable,
    vm: &VirtualMachine,
) -> Result<(BigUint, BigUint), HintError> {
    let c0_addr = vm.get_relocatable(base)?;
    let c1_addr = vm.get_relocatable((base + 1_usize).unwrap())?;
    let c0 = Uint384::from_base_addr(c0_addr, "base.c0", vm)?.pack();
    let c1 = Uint384::from_base_addr(c1_addr, "base.c1", vm)?.pack();
    Ok((c0, c1))
}

fn insert_field_element_from_var_name<const N: usize>(
    var_name: &str,
    coeffs: &[Uint384; N],
    vm: &mut VirtualMachine,
    ids_data: &HashMap<String, HintReference>,
    ap_tracking: &ApTracking,
) -> Result<(), HintError> {
    let field_struct_ptr = vm.add_memory_segment();

    // Create a segment and insert values for each coefficient
    for (i, coeff) in coeffs.iter().enumerate() {
        let c_ptr = vm.add_memory_segment();

        for j in 0..4 {
            vm.insert_value((c_ptr + j)?, coeff.limbs[j].clone().into_owned())?;
        }

        vm.insert_value((field_struct_ptr + i)?, c_ptr)?;
    }

    insert_value_from_var_name(var_name, field_struct_ptr, vm, ids_data, ap_tracking)
}
