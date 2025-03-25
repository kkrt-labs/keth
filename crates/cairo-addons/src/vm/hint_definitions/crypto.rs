use ark_bn254::{Fq12, Fq2, Fq6};
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

pub const HINTS: &[fn() -> Hint] = &[bnf2_multiplicative_inverse, bnf12_multiplicative_inverse];

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
            let mut coeffs = Vec::<BigUint>::new();
            for i in 0..12 {
                let coeff_addr = vm.get_relocatable((b_addr + (i as usize)).unwrap())?;
                let name = format!("c{}", i);
                let coeff = Uint384::from_base_addr(coeff_addr, &name, vm)?.pack();
                coeffs.push(coeff);
            }

            let fq2_real_0 = Fq2::new(coeffs[0].clone().into(), coeffs[1].clone().into());
            let fq2_real_1 = Fq2::new(coeffs[2].clone().into(), coeffs[3].clone().into());
            let fq2_real_2 = Fq2::new(coeffs[4].clone().into(), coeffs[5].clone().into());
            let fq2_imaginary_0 = Fq2::new(coeffs[6].clone().into(), coeffs[7].clone().into());
            let fq2_imaginary_1 = Fq2::new(coeffs[8].clone().into(), coeffs[9].clone().into());
            let fq2_imaginary_2 = Fq2::new(coeffs[10].clone().into(), coeffs[11].clone().into());
            let fq6_real = Fq6::new(fq2_real_0, fq2_real_1, fq2_real_2);
            let fq6_imaginary = Fq6::new(fq2_imaginary_0, fq2_imaginary_1, fq2_imaginary_2);
            let b = Fq12::new(fq6_real, fq6_imaginary);
            let b_inv = b.inverse().unwrap();
            let res = dbg!(b * b_inv);
            dbg!(assert_eq!(res, Fq12::ONE));

            let c0_u384 = Uint384::split(&b_inv.c0.c0.c0.into());
            let c1_u384 = Uint384::split(&b_inv.c0.c0.c1.into());
            let c2_u384 = Uint384::split(&b_inv.c0.c1.c0.into());
            let c3_u384 = Uint384::split(&b_inv.c0.c1.c1.into());
            let c4_u384 = Uint384::split(&b_inv.c0.c2.c0.into());
            let c5_u384 = Uint384::split(&b_inv.c0.c2.c1.into());
            let c6_u384 = Uint384::split(&b_inv.c1.c0.c0.into());
            let c7_u384 = Uint384::split(&b_inv.c1.c0.c1.into());
            let c8_u384 = Uint384::split(&b_inv.c1.c1.c0.into());
            let c9_u384 = Uint384::split(&b_inv.c1.c1.c1.into());
            let c10_u384 = Uint384::split(&b_inv.c1.c2.c0.into());
            let c11_u384 = Uint384::split(&b_inv.c1.c2.c1.into());

            let coeffs_u384 = [
                c0_u384, c1_u384, c2_u384, c3_u384, c4_u384, c5_u384, c6_u384, c7_u384, c8_u384,
                c9_u384, c10_u384, c11_u384,
            ];

            let bnf2_struct_ptr = vm.add_memory_segment();
            for i in 0..12 {
                let coeff_ptr = vm.add_memory_segment();
                for j in 0..4 {
                    vm.insert_value(
                        (coeff_ptr + j)?,
                        coeffs_u384[i].limbs[j].clone().into_owned(),
                    )?;
                }
                vm.insert_value((bnf2_struct_ptr + i)?, coeff_ptr)?;
            }
            insert_value_from_var_name("b_inv", bnf2_struct_ptr, vm, ids_data, ap_tracking)?;
            Ok(())
        },
    )
}
