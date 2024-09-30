use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::{
            builtin_hint_processor_definition::{BuiltinHintProcessor, HintFunc},
            hint_utils::get_ptr_from_var_name,
            memcpy_hint_utils::add_segment,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::{exec_scope::ExecutionScopes, relocatable::MaybeRelocatable},
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use ef_tests::models::Block;
use reth_primitives::U256;
use std::{collections::HashMap, fmt, rc::Rc};

/// The type of a hint execution result.
pub type HintExecutionResult = Result<(), HintError>;

/// A wrapper around [`BuiltinHintProcessor`] to manage hint registration.
pub struct KakarotHintProcessor {
    /// The underlying [`BuiltinHintProcessor`].
    processor: BuiltinHintProcessor,
}

/// Implementation of `Debug` for `KakarotHintProcessor`.
impl fmt::Debug for KakarotHintProcessor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KakarotHintProcessor")
            .field("extra_hints", &self.processor.extra_hints.keys())
            .field("run_resources", &"...")
            .finish()
    }
}

impl Default for KakarotHintProcessor {
    fn default() -> Self {
        Self::new_empty().with_hint(add_segment_hint())
    }
}

impl KakarotHintProcessor {
    /// Creates a new, empty [`KakarotHintProcessor`].
    pub fn new_empty() -> Self {
        Self { processor: BuiltinHintProcessor::new_empty() }
    }

    /// Adds a hint to the [`KakarotHintProcessor`].
    ///
    /// This method allows you to register a hint by providing a [`Hint`] instance.
    pub fn with_hint(mut self, hint: Hint) -> Self {
        self.processor.add_hint(hint.name.clone(), hint.func.clone());
        self
    }

    /// Returns the underlying [`BuiltinHintProcessor`].
    ///
    /// This allows the processor to be used elsewhere.
    pub fn build(self) -> BuiltinHintProcessor {
        self.processor
    }
}

/// A generic structure to encapsulate a hint with a closure that contains the specific logic.
pub struct Hint {
    /// The name of the hint.
    name: String,
    /// The function containing the hint logic.
    func: Rc<HintFunc>,
}

impl fmt::Debug for Hint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Hint").field("name", &self.name).field("func", &"...").finish()
    }
}

impl Hint {
    /// Creates a new [`Hint`] with the specified name and function logic.
    ///
    /// The logic is passed as a closure, which will be executed when the hint is triggered.
    pub fn new<F>(name: String, logic: F) -> Self
    where
        F: Fn(
                &mut VirtualMachine,
                &mut ExecutionScopes,
                &HashMap<String, HintReference>,
                &ApTracking,
                &HashMap<String, Felt252>,
            ) -> HintExecutionResult
            + 'static
            + Sync,
    {
        Self { name, func: Rc::new(HintFunc(Box::new(logic))) }
    }
}

/// Generates a hint to add a new memory segment.
///
/// This function adds a hint to the `HintProcessor` that creates a new memory segment in the
/// virtual machine. It maps the current memory pointer (`ap`) to the newly added segment.
pub fn add_segment_hint() -> Hint {
    Hint::new(
        String::from("memory[ap] = to_felt_or_relocatable(segments.add())"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> HintExecutionResult {
            // Calls the function to add a new memory segment to the VM.
            add_segment(vm)
        },
    )
}

pub fn block_hint(block: Block) -> Hint {
    let block_transactions = block.transactions.unwrap_or_default();
    let header = block.block_header.clone().unwrap();

    Hint::new(
        String::from("block"),
        move |vm: &mut VirtualMachine,
              _exec_scopes: &mut ExecutionScopes,
              ids_data: &HashMap<String, HintReference>,
              ap_tracking: &ApTracking,
              _constants: &HashMap<String, Felt252>|
              -> HintExecutionResult {
            // We retrieve the `env` pointer from the `ids_data` hashmap.
            // This pointer is used to store the block-related values in the VM.
            let env_ptr = get_ptr_from_var_name("block", vm, ids_data, ap_tracking)?;

            // Block header values are stored in a vector.
            let mut block_header = Vec::new();

            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.base_fee_per_gas.unwrap_or_default().to_be_bytes::<{ U256::BYTES }>(),
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.blob_gas_used.unwrap_or_default().to_be_bytes::<{ U256::BYTES }>(),
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from(header.bloom.len())));
            block_header
                .push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.bloom.0 .0)));
            block_header
                .push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.coinbase.0 .0)));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.difficulty.to_be_bytes::<{ U256::BYTES }>(),
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.excess_blob_gas.unwrap().to_be_bytes::<{ U256::BYTES }>(),
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from(header.extra_data.len())));
            block_header
                .push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.extra_data.0)));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.gas_limit.to_be_bytes::<{ U256::BYTES }>(),
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.gas_used.to_be_bytes::<{ U256::BYTES }>(),
            )));
            block_header
                .push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.hash.0[16..])));
            block_header
                .push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.hash.0[0..16])));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.mix_hash.0[16..],
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.mix_hash.0[0..16],
            )));
            block_header
                .push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.nonce.0)));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.number.to_be_bytes::<{ U256::BYTES }>(),
            )));

            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.parent_beacon_block_root.unwrap().0[16..],
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.parent_beacon_block_root.unwrap().0[0..16],
            )));

            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.parent_hash.0[16..],
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.parent_hash.0[0..16],
            )));

            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.receipt_trie.0[16..],
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.receipt_trie.0[0..16],
            )));

            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.state_root.0[16..],
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.state_root.0[0..16],
            )));

            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.timestamp.to_be_bytes::<{ U256::BYTES }>(),
            )));

            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.transactions_trie.0[16..],
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.transactions_trie.0[0..16],
            )));

            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.uncle_hash.0[16..],
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.uncle_hash.0[0..16],
            )));

            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.withdrawals_root.unwrap().0[16..],
            )));
            block_header.push(MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.withdrawals_root.unwrap().0[0..16],
            )));

            // Transaction len
            let mut transaction_len = Vec::new();

            transaction_len.push(MaybeRelocatable::from(Felt252::from(block_transactions.len())));

            // Transactions
            let mut transactions = Vec::new();

            for transaction in &block_transactions {}

            vm.load_data(env_ptr, &[block_header, transaction_len, transactions].concat())
                .map_err(HintError::Memory)?;

            Ok(())
        },
    )
}

#[cfg(test)]
mod test {
    use super::*;
    use std::{fs, path::PathBuf};

    #[test]
    fn test_block_hint() {
        // Read the JSON file containing the hint.
        let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("testdata/block.json");
        let content = fs::read_to_string(path).unwrap();

        let block: Block = serde_json::from_str(&content).unwrap();

        println!("{:?}", block);
    }
}
