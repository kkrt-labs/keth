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

use crate::vm::{hint_utils::Uint384, hints::Hint};

pub const HINTS: &[fn() -> Hint] = &[bnf2_multiplicative_inverse];

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

fn fq2_inverse(a: &Fq2) -> Option<Fq2> {
    // "High-Speed Software Implementation of the Optimal Ate Pairing
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
            let a_addr = get_ptr_from_var_name("a", vm, ids_data, ap_tracking)?;
            let c0_addr = vm.get_relocatable(a_addr)?;
            let c1_addr = vm.get_relocatable((a_addr + 1_usize).unwrap())?;
            let c0 = Uint384::from_base_addr(c0_addr, "a.c0", vm)?.pack();
            let c1 = Uint384::from_base_addr(c1_addr, "a.c1", vm)?.pack();

            // To compute the multiplicative inverse, we use the substrate-bn package (also used by
            // revm). A Fq2 struct is made of two Fq elements which can be constructed
            // from a U256.

            let c0_fq = Fq::from_slice(&c0.to_bytes_le()).unwrap();
            let c1_fq = Fq::from_slice(&c1.to_bytes_le()).unwrap();

            let a = Fq2::new(c0_fq, c1_fq);
            let a_inv = fq2_inverse(&a).unwrap();

            let a_inv_c0 = a_inv.real();
            let a_inv_c1 = a_inv.imaginary();
            let a_inv_c0_be_slice: &mut [u8] = &mut [];
            let a_inv_c1_be_slice: &mut [u8] = &mut [];
            a_inv_c0.to_big_endian(a_inv_c0_be_slice).unwrap();
            a_inv_c1.to_big_endian(a_inv_c1_be_slice).unwrap();

            let c0_u384 = Uint384::split(&BigUint::from_bytes_be(&a_inv_c0_be_slice));
            let c1_u384 = Uint384::split(&BigUint::from_bytes_be(&a_inv_c1_be_slice));

            insert_value_from_var_name("a_inv", Felt252::from(0), vm, ids_data, ap_tracking)?;
            Ok(())
        },
    )
}
