use crate::{db::Database, exex::CHAIN_SPEC};
use alloy_primitives::U256;
use reth::primitives::BlockBody;
use reth_execution_errors::BlockValidationError;
use reth_node_api::{ConfigureEvm, ConfigureEvmEnv};
use reth_node_ethereum::EthEvmConfig;
use reth_primitives::{
    revm_primitives::{CfgEnvWithHandlerCfg, EVMError, ExecutionResult, ResultAndState},
    Block, BlockWithSenders, EthereumHardfork, Header, Receipt, SealedBlockWithSenders,
    TransactionSigned, TransactionSignedEcRecovered,
};
use reth_revm::{
    db::{states::bundle_state::BundleRetention, BundleState},
    DBBox, DatabaseCommit, Evm, StateBuilder, StateDBBox,
};
use reth_tracing::tracing::debug;

/// Executes a rollup block, processing the given transactions, and returns the block with recovered
/// senders, the resulting bundle state, the list of receipts, and the execution results.
pub async fn execute_block(
    db: &mut Database,
    block: &SealedBlockWithSenders,
    txs: Vec<TransactionSignedEcRecovered>,
) -> eyre::Result<(BlockWithSenders, BundleState, Vec<Receipt>, Vec<ExecutionResult>)> {
    // Extract the header from the provided block.
    let header = block.header();

    // Configure the EVM with default settings and associate it with the database and block header.
    let evm_config = EthEvmConfig::new(CHAIN_SPEC.clone());
    let mut evm = configure_evm(&evm_config, db, header);

    // Execute the transactions in the block and retrieve the executed transactions, receipts, and
    // results.
    let (executed_txs, receipts, results) = execute_transactions(&mut evm, header, txs)?;

    // Construct a new block using the executed transactions and header, and attempt to recover
    // senders.
    let block = Block {
        header: header.clone(),
        body: BlockBody { transactions: executed_txs, ..Default::default() },
    }
    .with_recovered_senders()
    .ok_or_else(|| eyre::eyre!("Failed to recover senders for transactions"))?;

    // Extract the current bundle state from the EVM's database.
    let bundle = evm.db_mut().take_bundle();

    // Return the constructed block with senders, the bundle state, the transaction receipts, and
    // the execution results.
    Ok((block, bundle, receipts, results))
}

/// Configures the EVM with the given database and block header.
pub fn configure_evm<'a>(
    config: &'a EthEvmConfig,
    db: &'a mut Database,
    header: &Header,
) -> Evm<'a, (), StateDBBox<'a, eyre::Report>> {
    // Initialize the EVM with the provided database and configure it to update the bundle state.
    let mut evm = config.evm(
        StateBuilder::new_with_database(Box::new(db) as DBBox<'_, eyre::Report>)
            .with_bundle_update()
            .build(),
    );

    // Set the state clearing flag based on the active fork at the given block number.
    evm.db_mut().set_state_clear_flag(
        CHAIN_SPEC.fork(EthereumHardfork::Cancun).active_at_block(header.number),
    );

    // Create the configuration and block environment with the specified spec ID.
    let mut cfg = CfgEnvWithHandlerCfg::new_with_spec_id(evm.cfg().clone(), evm.spec_id());

    // Populate the configuration and block environment with additional details.
    config.fill_cfg_and_block_env(&mut cfg, evm.block_mut(), header, U256::ZERO);

    // Update the EVM's configuration environment with the newly populated configuration.
    *evm.cfg_mut() = cfg.cfg_env;

    // Return the configured EVM instance.
    evm
}

/// Execute a list of transactions, returning the executed transactions, their receipts, and
/// execution results.
pub fn execute_transactions(
    evm: &mut Evm<'_, (), StateDBBox<'_, eyre::Report>>,
    header: &Header,
    transactions: Vec<TransactionSignedEcRecovered>,
) -> eyre::Result<(Vec<TransactionSigned>, Vec<Receipt>, Vec<ExecutionResult>)> {
    // Initializationof vectors and variables
    let mut receipts = Vec::with_capacity(transactions.len());
    let mut executed_txs = Vec::with_capacity(transactions.len());
    let mut results = Vec::with_capacity(transactions.len());
    let mut cumulative_gas_used = 0;

    // Iterates through each transaction and sender in the list.
    for transaction in transactions {
        let (transaction, sender) = transaction.to_components();
        // Calculates the available gas in the block after previous transactions.
        let block_available_gas = header.gas_limit - cumulative_gas_used;
        // Ensures that the current transaction does not exceed the block's available gas.
        if transaction.gas_limit() > block_available_gas {
            return Err(BlockValidationError::TransactionGasLimitMoreThanAvailableBlockGas {
                transaction_gas_limit: transaction.gas_limit(),
                block_available_gas,
            }
            .into());
        }

        // Configures the EVM environment for the current transaction and sender.
        EthEvmConfig::new(CHAIN_SPEC.clone()).fill_tx_env(evm.tx_mut(), &transaction, sender);

        // Executes the transaction using the EVM.
        let ResultAndState { result, state } = match evm.transact() {
            // Retrieves the result and state if the transaction is successful.
            Ok(result) => result,
            // Handles and logs errors specific to the transaction, then skips to the next one.
            Err(EVMError::Transaction(err)) => {
                debug!(%err, ?transaction, "Skipping invalid transaction");
                continue;
            }
            // Bails out of the function if a non-transaction-specific error occurs.
            Err(err) => eyre::bail!(err),
        };

        debug!(?transaction, ?result, ?state, "Executed transaction");

        // Commits the state changes from the transaction to the database.
        evm.db_mut().commit(state);

        // Updates the cumulative gas used by adding the gas used by the current transaction.
        cumulative_gas_used += result.gas_used();

        // Constructs a receipt for the transaction
        receipts.push(Receipt {
            tx_type: transaction.tx_type(),
            success: result.is_success(),
            cumulative_gas_used,
            logs: result.logs().iter().cloned().map(Into::into).collect(),
        });

        // Adds the executed transaction to the list of executed transactions.
        executed_txs.push(transaction);
        // Adds the execution result to the list of results.
        results.push(result);
    }

    // Merges the state transitions, handling any necessary reverts.
    evm.db_mut().merge_transitions(BundleRetention::Reverts);

    // Returns the executed transactions, receipts, and results.
    //
    // Not sure everything will be useful, but it's better to return everything for now.
    Ok((executed_txs, receipts, results))
}
