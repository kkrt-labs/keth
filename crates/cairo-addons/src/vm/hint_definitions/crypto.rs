use ark_bn254::{Fq, Fq2, Fq6};
use ark_ff::Field;
use num_bigint::BigUint;
use std::collections::HashMap;

use ark_bn254::Fq12;
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

pub const HINTS: &[fn() -> Hint] =
    &[bnf_multiplicative_inverse, bnf2_multiplicative_inverse, bnf12_multiplicative_inverse];

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

            let b = Fq::from(c0);
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

            let b = Fq2::new(c0.into(), c1.into());
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

pub fn bnf12_multiplicative_inverse() -> Hint {
    Hint::new(
        String::from("bnf12_multiplicative_inverse"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let b_addr = get_ptr_from_var_name("b", vm, ids_data, ap_tracking)?;

            let mut packed_coeffs: Vec<BigUint> = Vec::with_capacity(12);
            for i in 0..12 {
                let ci_addr_ptr = (b_addr + i)?;
                let ci_addr = vm.get_relocatable(ci_addr_ptr)?;
                let ci_u384 = Uint384::from_base_addr(ci_addr, &format!("b.c{}", i), vm)?;
                packed_coeffs.push(ci_u384.pack());
            }

            let fq_coeffs: Vec<Fq> = packed_coeffs.into_iter().map(Fq::from).collect();
            let fq2_coeffs: Vec<Fq2> =
                fq_coeffs.chunks_exact(2).map(|chunk| Fq2::new(chunk[0], chunk[1])).collect();
            if fq2_coeffs.len() != 6 {
                return Err(HintError::CustomHint(
                    format!(
                        "Expected 12 coefficients for BNF12 (6 Fq2), found {}",
                        fq_coeffs.len()
                    )
                    .into(),
                ));
            }
            let fq6_coeffs: Vec<Fq6> = fq2_coeffs
                .chunks_exact(3)
                .map(|chunk| Fq6::new(chunk[0], chunk[1], chunk[2]))
                .collect();
            let b = Fq12::new(fq6_coeffs[0], fq6_coeffs[1]);
            println!("{:?}", b);

            let b_inv = b.inverse().unwrap();
            println!("{:?}", b_inv);

            // ASSERTION
            let b_inv_b = b * b_inv;
            println!("ASSERTION : {:?}", b_inv_b);

            let mut b_inv_fq_coeffs = Vec::with_capacity(12);
            b_inv_fq_coeffs.extend([b_inv.c0.c0.c0, b_inv.c0.c0.c1]);
            b_inv_fq_coeffs.extend([b_inv.c0.c1.c0, b_inv.c0.c1.c1]);
            b_inv_fq_coeffs.extend([b_inv.c0.c2.c0, b_inv.c0.c2.c1]);
            b_inv_fq_coeffs.extend([b_inv.c1.c0.c0, b_inv.c1.c0.c1]);
            b_inv_fq_coeffs.extend([b_inv.c1.c1.c0, b_inv.c1.c1.c1]);
            b_inv_fq_coeffs.extend([b_inv.c1.c2.c0, b_inv.c1.c2.c1]);
            let b_inv_coeffs_u384: Vec<Uint384> =
                b_inv_fq_coeffs.iter().map(|fq| Uint384::split(&(*fq).into())).collect();

            println!("{:?}", b_inv_coeffs_u384);

            let bnf12_struct_ptr = vm.add_memory_segment();
            let mut coeff_ptrs: Vec<Relocatable> = Vec::with_capacity(12);

            for coeff in b_inv_coeffs_u384 {
                let ci_ptr = vm.add_memory_segment();
                coeff_ptrs.push(ci_ptr);
                for limb_idx in 0..4 {
                    vm.insert_value(
                        (ci_ptr + limb_idx)?,
                        coeff.limbs[limb_idx].clone().into_owned(),
                    )?;
                }
            }

            for (i, ptr) in coeff_ptrs.iter().enumerate() {
                vm.insert_value((bnf12_struct_ptr + i)?, ptr)?;
            }

            insert_value_from_var_name("b_inv", bnf12_struct_ptr, vm, ids_data, ap_tracking)?;

            Ok(())
        },
    )
}
