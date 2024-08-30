use crate::{db::Database, exex::DATABASE_PATH};
use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::builtin_hint_processor_definition::{
            BuiltinHintProcessor, HintFunc,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use rusqlite::Connection;
use std::{collections::HashMap, fmt, rc::Rc};

/// A wrapper around [`BuiltinHintProcessor`] to manage hint registration.
pub struct KakarotBuiltinHintProcessor {
    /// The underlying [`BuiltinHintProcessor`].
    processor: BuiltinHintProcessor,
}

/// Implementation of `Debug` for `KakarotBuiltinHintProcessor`.
impl fmt::Debug for KakarotBuiltinHintProcessor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KakarotBuiltinHintProcessor")
            .field("extra_hints", &self.processor.extra_hints.keys())
            .field("run_resources", &"...")
            .finish()
    }
}

impl Default for KakarotBuiltinHintProcessor {
    fn default() -> Self {
        Self::new_empty().with_hint(print_tx_hint())
    }
}

impl KakarotBuiltinHintProcessor {
    /// Creates a new, empty [`KakarotBuiltinHintProcessor`].
    pub fn new_empty() -> Self {
        Self { processor: BuiltinHintProcessor::new_empty() }
    }

    /// Adds a hint to the [`KakarotBuiltinHintProcessor`].
    ///
    /// This method allows you to register a hint by providing a [`Hint`] instance.
    pub fn with_hint(mut self, hint: Hint) -> Self {
        hint.register(&mut self.processor);
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
            ) -> Result<(), HintError>
            + 'static
            + Sync,
    {
        Self { name, func: Rc::new(HintFunc(Box::new(logic))) }
    }

    /// Registers the hint in the hint processor.
    ///
    /// This method allows the hint to be recognized and executed by the hint processor.
    pub fn register(&self, hint_processor: &mut BuiltinHintProcessor) {
        hint_processor.add_hint(self.name.clone(), self.func.clone());
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
