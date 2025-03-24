use num_bigint::BigUint;
use std::collections::HashMap;
use substrate_bn::{arith::U256, Fq, Fq2};

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

use crate::vm::{
    hint_utils::{write_collection_to_addr, Uint384},
    hints::Hint,
};

pub const HINTS: &[fn() -> Hint] = &[bnf2_multiplicative_inverse];

// Function adapted from the `substrate_bn` crate as not publicly available.
// Link: https://github.com/paritytech/bn/blob/63f8c587356a67b33c7396af98e065b66fca5dda/src/fields/fq2.rs#L7
fn fq_non_residue() -> Fq {
    // (q - 1) is a quadratic non-residue in Fq
    // 21888242871839275222246405745257275088696311157297823662689037894645226208582
    Fq::from_u256(U256::from([
        0x68c3488912edefaa,
        0x8d087f6872aabf4f,
        0x51e1a24709081231,
        0x2259d6b14729c0fa,
    ]))
    .unwrap()
}

// Function adapted from the `substrate_bn` crate as not publicly available.
// Link: https://github.com/paritytech/bn/blob/63f8c587356a67b33c7396af98e065b66fca5dda/src/fields/fq2.rs#L119
// TODO: Investigate why not available,
fn fq2_inverse(a: &Fq2) -> Option<Fq2> {
    // "High-Speed Software Implementation of the Optimal Ate Pairing
    // over Barreto–Naehrig Curves"; Algorithm 8
    let c0 = a.real();
    let c1 = a.imaginary();

    (c0 * c0 - (c1 * c1 * fq_non_residue())).inverse().map(|t| Fq2::new(c0 * t, -(c1 * t)))
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

            // To compute the multiplicative inverse, we use the `substrate_bn` crate (also used
            // by revm). A Fq2 struct is made of two Fq elements which can be
            // constructed from a U256.
            // In this crate, bytes are expected to be in Big Endian (BE).

            let c0_fq = Fq::from_slice(&c0.to_bytes_be()).unwrap();
            let c1_fq = Fq::from_slice(&c1.to_bytes_be()).unwrap();

            let b = Fq2::new(c0_fq, c1_fq);
            let b_inv = fq2_inverse(&b).unwrap();

            let b_inv_c0 = b_inv.real();
            let b_inv_c1 = b_inv.imaginary();
            let b_inv_c0_be_slice: &mut [u8] = &mut [];
            let b_inv_c1_be_slice: &mut [u8] = &mut [];
            b_inv_c0.to_big_endian(b_inv_c0_be_slice).unwrap();
            b_inv_c1.to_big_endian(b_inv_c1_be_slice).unwrap();

            let c0_u384 = Uint384::split(&BigUint::from_bytes_be(b_inv_c0_be_slice));
            let c1_u384 = Uint384::split(&BigUint::from_bytes_be(b_inv_c1_be_slice));
            let bnf2_struct_ptr = vm.add_memory_segment();
            let c0_ptr = vm.add_memory_segment();
            let c1_ptr = vm.add_memory_segment();

            for i in 0..4 {
                vm.insert_value((c0_ptr + i)?, c0_u384.limbs[i].clone().into_owned())?;
            }
            for i in 0..4 {
                vm.insert_value((c1_ptr + i)?, c1_u384.limbs[i].clone().into_owned())?;
            }
            vm.insert_value(bnf2_struct_ptr, c0_ptr)?;
            vm.insert_value((bnf2_struct_ptr + 1_usize).unwrap(), c1_ptr)?;
            insert_value_from_var_name("b_inv", bnf2_struct_ptr, vm, ids_data, ap_tracking)?;
            Ok(())
        },
    )
}
