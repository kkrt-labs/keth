use crate::{db::Database, exex::DATABASE_PATH};
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
use reth_primitives::{SealedBlock, TransactionSignedEcRecovered};
use rusqlite::Connection;
use std::{collections::HashMap, fmt, rc::Rc};

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
        Self::new_empty().with_hint(print_tx_hint()).with_hint(add_segment_hint())
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

    /// Adds a block to the [`KakarotHintProcessor`].
    ///
    /// This method allows you to register a block by providing a [`SealedBlockWithSenders`]
    /// instance.
    pub fn with_block_and_transaction(
        self,
        block: SealedBlock,
        transaction: TransactionSignedEcRecovered,
    ) -> Self {
        self.with_hint(block_info_hint(block, transaction))
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
            ) -> Result<(), HintError>
            + 'static
            + Sync,
    {
        Self { name, func: Rc::new(HintFunc(Box::new(logic))) }
    }
}

/// Public function to create the `print_latest_block_transactions` hint.
///
/// This function returns a new `Hint` instance with the specified name and logic.
pub fn print_tx_hint() -> Hint {
    Hint::new(
        String::from("print_latest_block_transactions"),
        |_vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> {
            // Open the SQLite database connection.
            let connection = Connection::open(DATABASE_PATH)
                .map_err(|e| HintError::CustomHint(e.to_string().into_boxed_str()))?;

            // Initialize the database with the connection.
            let db = Database::new(connection)
                .map_err(|e| HintError::CustomHint(e.to_string().into_boxed_str()))?;

            // Retrieve the latest block from the database.
            let latest_block = db
                .latest_block()
                .map_err(|e| HintError::CustomHint(e.to_string().into_boxed_str()))?;

            // If a block was found, print each transaction hash.
            if let Some(block) = latest_block {
                for tx in &block.body {
                    println!("Block: {}, transaction hash: {}", block.number, tx.hash());
                }
            }

            Ok(())
        },
    )
}

/// Generates a hint to store block information in the `Environment` model.
pub fn block_info_hint(block: SealedBlock, transaction: TransactionSignedEcRecovered) -> Hint {
    Hint::new(
        String::from("block_info"),
        move |vm: &mut VirtualMachine,
              _exec_scopes: &mut ExecutionScopes,
              ids_data: &HashMap<String, HintReference>,
              ap_tracking: &ApTracking,
              _constants: &HashMap<String, Felt252>|
              -> Result<(), HintError> {
            // We retrieve the `env` pointer from the `ids_data` hashmap.
            // This pointer is used to store the block-related values in the VM.
            let env_ptr = get_ptr_from_var_name("env", vm, ids_data, ap_tracking)?;

            // We load the block-related values into the VM.
            //
            // The values are loaded in the order they are defined in the `Environment` model.
            // We start at the `env` pointer.
            let _ = vm
                .load_data(
                    env_ptr,
                    &[
                        MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                            &transaction.signer().0 .0,
                        )),
                        MaybeRelocatable::from(Felt252::from(
                            transaction.effective_gas_price(block.base_fee_per_gas),
                        )),
                        MaybeRelocatable::from(Felt252::from(
                            transaction.chain_id().unwrap_or_default(),
                        )),
                        MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                            &block.mix_hash.0[16..],
                        )),
                        MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                            &block.mix_hash.0[0..16],
                        )),
                        MaybeRelocatable::from(Felt252::from(block.number)),
                        MaybeRelocatable::from(Felt252::from(block.gas_limit)),
                        MaybeRelocatable::from(Felt252::from(block.timestamp)),
                        MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                            &block.beneficiary.0 .0,
                        )),
                        MaybeRelocatable::from(Felt252::from(
                            block.base_fee_per_gas.unwrap_or_default(),
                        )),
                    ],
                )
                .map_err(HintError::Memory)?;

            Ok(())
        },
    )
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
         -> Result<(), HintError> {
            // Calls the function to add a new memory segment to the VM.
            add_segment(vm)
        },
    )
}
