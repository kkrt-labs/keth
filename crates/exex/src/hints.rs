use crate::{db::Database, exex::DATABASE_PATH};
use cairo_vm::{
    hint_processor::hint_processor_definition::HintReference,
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use rusqlite::Connection;
use std::collections::HashMap;

/// The hint name for the `print_latest_block_transactions` function.
///
/// This is just a string constant that is used to identify the hint in the hint processor.
pub const KETH_PRINT_TX_HASHES: &str = "print_latest_block_transactions";

/// Prints transaction hashes from the latest block in the SQLite database.
///
/// This function connects to an SQLite database specified by `DATABASE_PATH`, retrieves the latest
/// block, and prints the hash of each transaction contained in that block.
pub fn print_latest_block_transactions(
    _vm: &mut VirtualMachine,
    _exec_scopes: &mut ExecutionScopes,
    _ids_data: &HashMap<String, HintReference>,
    _ap_tracking: &ApTracking,
    _constants: &HashMap<String, Felt252>,
) -> Result<(), HintError> {
    // Open the SQLite database connection.
    let connection = Connection::open(DATABASE_PATH)
        .map_err(|e| HintError::CustomHint(e.to_string().into_boxed_str()))?;

    // Initialize the database with the connection.
    let db = Database::new(connection)
        .map_err(|e| HintError::CustomHint(e.to_string().into_boxed_str()))?;

    // Retrieve the latest block from the database.
    let latest_block =
        db.latest_block().map_err(|e| HintError::CustomHint(e.to_string().into_boxed_str()))?;

    // Check if a latest block was found.
    if let Some(block) = latest_block {
        // Iterate over each transaction in the block's body.
        for tx in &block.body {
            println!("Block: {}, transaction hash: {}", block.number, tx.hash());
        }
    }

    Ok(())
}
