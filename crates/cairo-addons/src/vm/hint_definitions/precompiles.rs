use std::collections::HashMap;

use crate::vm::hint_utils::deserialize_sequence;
use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::insert_value_from_var_name,
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use num_bigint::BigUint;
use num_traits::{ToPrimitive, Zero};

use crate::vm::{
    hint_utils::{serialize_sequence, Uint256},
    hints::Hint,
};

pub const HINTS: &[fn() -> Hint] = &[modexp_gas, modexp_output];

const WORD_SIZE: u32 = 8;
const MAX_EXP_LEN: u32 = 32;
const MIN_GAS_COST: u32 = 200;
const GAS_DIVISOR: u32 = 3;

pub fn modexp_gas() -> Hint {
    Hint::new(
        String::from("modexp_gas"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let base_length = Uint256::from_var_name("base_length", vm, ids_data, ap_tracking)?;
            let exp_length = Uint256::from_var_name("exp_length", vm, ids_data, ap_tracking)?;
            let modulus_length =
                Uint256::from_var_name("modulus_length", vm, ids_data, ap_tracking)?;
            let exp_head = Uint256::from_var_name("exp_head", vm, ids_data, ap_tracking)?;

            let max_length = std::cmp::max(
                base_length.low.as_ref().to_biguint(),
                modulus_length.low.as_ref().to_biguint(),
            );
            let words = (&max_length + BigUint::from(WORD_SIZE - 1)) / BigUint::from(WORD_SIZE);
            let multiplication_complexity = &words * &words;

            let exp_len = exp_length.low.as_ref().to_biguint();
            let exp_head_val = exp_head.pack();

            let iteration_count = if &exp_len <= &BigUint::from(MAX_EXP_LEN) &&
                exp_head_val.is_zero()
            {
                BigUint::zero()
            } else if &exp_len <= &BigUint::from(MAX_EXP_LEN) {
                exp_head_val.bits().checked_sub(1).map(BigUint::from).unwrap_or_else(BigUint::zero)
            } else {
                let length_part =
                    &BigUint::from(WORD_SIZE) * (&exp_len - BigUint::from(MAX_EXP_LEN));
                let bits_part = exp_head_val.bits().checked_sub(1).unwrap_or(0);
                &length_part + bits_part
            };

            let iteration_count = std::cmp::max(iteration_count, BigUint::from(1u32));
            let cost = &multiplication_complexity * &iteration_count;
            let gas_cost =
                std::cmp::max(BigUint::from(MIN_GAS_COST), &cost / BigUint::from(GAS_DIVISOR));

            insert_value_from_var_name("gas", Felt252::from(gas_cost), vm, ids_data, ap_tracking)
        },
    )
}

pub fn modexp_output() -> Hint {
    Hint::new(
        String::from("modexp_output"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            let mut bytes_to_vec = |name: &str| -> Result<Vec<u8>, HintError> {
                Ok(serialize_sequence(name, vm, ids_data, ap_tracking)?
                    .iter()
                    .filter_map(|x| x.to_u8())
                    .collect())
            };

            let base_bytes = bytes_to_vec("base")?;
            let exp_bytes = bytes_to_vec("exp")?;
            let mod_bytes = bytes_to_vec("modulus")?;

            let base_int = BigUint::from_bytes_be(&base_bytes);
            let exp_int = BigUint::from_bytes_be(&exp_bytes);
            let mod_int = BigUint::from_bytes_be(&mod_bytes);

            let result = if mod_int.is_zero() {
                vec![0u8; mod_bytes.len()]
            } else {
                let result = base_int.modpow(&exp_int, &mod_int);
                let bytes = result.to_bytes_be();
                let target_len = mod_bytes.len();

                if bytes.len() < target_len {
                    let mut padded = vec![0u8; target_len];
                    padded[target_len - bytes.len()..].copy_from_slice(&bytes);
                    padded
                } else {
                    bytes
                }
            };

            let base = deserialize_sequence(result, vm)?;
            insert_value_from_var_name("result", base, vm, ids_data, ap_tracking)
        },
    )
}
