use std::collections::HashMap;

use crate::vm::{
    hint_utils::{split, write_result_to_ap, Uint384},
    hints::Hint,
};
use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{
            get_integer_from_var_name, get_ptr_from_var_name, insert_value_from_var_name,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use num_traits::Zero;

pub const HINTS: &[fn() -> Hint] = &[
    felt_to_uint384_split_hint,
    has_six_uint384_remaining_hint,
    has_one_uint384_remaining_hint,
    x_mod_p_eq_y_mod_p_hint,
    x_is_neg_y_mod_p_hint,
];

pub fn has_six_uint384_remaining_hint() -> Hint {
    Hint::new(
        String::from("has_six_uint384_remaining_hint"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let elements_end = get_ptr_from_var_name("elements_end", vm, ids_data, ap_tracking)?;
            let elements = get_ptr_from_var_name("elements", vm, ids_data, ap_tracking)?;
            let elements_len = match elements_end - elements {
                Ok(x) => x,
                Err(_e) => {
                    return write_result_to_ap(false, 1, vm);
                }
            };
            let n_limbs = get_integer_from_var_name("N_LIMBS_HINT", vm, ids_data, ap_tracking)?;
            let has_six_uint384_remaining =
                Felt252::from(elements_len) >= Felt252::from(6) * n_limbs;
            write_result_to_ap(has_six_uint384_remaining, 1, vm)
        },
    )
}

pub fn has_one_uint384_remaining_hint() -> Hint {
    Hint::new(
        String::from("has_one_uint384_remaining_hint"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let elements_end = get_ptr_from_var_name("elements_end", vm, ids_data, ap_tracking)?;
            let elements = get_ptr_from_var_name("elements", vm, ids_data, ap_tracking)?;
            let elements_len = match elements_end - elements {
                Ok(x) => x,
                Err(_e) => {
                    return write_result_to_ap(false, 1, vm);
                }
            };
            let n_limbs = get_integer_from_var_name("N_LIMBS_HINT", vm, ids_data, ap_tracking)?;
            let has_one_uint384_remaining = Felt252::from(elements_len) >= n_limbs;
            write_result_to_ap(has_one_uint384_remaining, 1, vm)
        },
    )
}

pub fn felt_to_uint384_split_hint() -> Hint {
    Hint::new(
        String::from("felt_to_uint384_split_hint"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let x = get_integer_from_var_name("x", vm, ids_data, ap_tracking)?.to_biguint();
            let limbs = split(&x, 4, 96);
            assert!(limbs[3] == Felt252::ZERO);
            insert_value_from_var_name("d0", limbs[0], vm, ids_data, ap_tracking)?;
            insert_value_from_var_name("d1", limbs[1], vm, ids_data, ap_tracking)?;
            insert_value_from_var_name("d2", limbs[2], vm, ids_data, ap_tracking)?;
            Ok(())
        },
    )
}

pub fn x_mod_p_eq_y_mod_p_hint() -> Hint {
    Hint::new(
        String::from("x_mod_p_eq_y_mod_p_hint"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let x = Uint384::from_var_name("x", vm, ids_data, ap_tracking)?.pack();
            let y = Uint384::from_var_name("y", vm, ids_data, ap_tracking)?.pack();
            let p = Uint384::from_var_name("p", vm, ids_data, ap_tracking)?.pack();
            let x_mod_p = x % p.clone();
            let y_mod_p = y % p;
            write_result_to_ap(x_mod_p == y_mod_p, 1, vm)
        },
    )
}

pub fn x_is_neg_y_mod_p_hint() -> Hint {
    Hint::new(
        String::from("x_is_neg_y_mod_p_hint"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let x = Uint384::from_var_name("x", vm, ids_data, ap_tracking)?.pack_bigint();
            let y = Uint384::from_var_name("y", vm, ids_data, ap_tracking)?.pack_bigint();
            let p = Uint384::from_var_name("p", vm, ids_data, ap_tracking)?.pack_bigint();

            // For modular negation, we use the formula: -y mod p = (p - (y mod p)) mod p
            let x_mod_p = x % p.clone();
            let y_mod_p = y % p.clone();
            let neg_y_mod_p = if y_mod_p.is_zero() {
                y_mod_p // If y mod p is 0, then -y mod p is also 0
            } else {
                (&p - &y_mod_p) % &p
            };

            write_result_to_ap(x_mod_p == neg_y_mod_p, 1, vm)
        },
    )
}
