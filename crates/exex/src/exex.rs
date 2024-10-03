use crate::{db::Database, hints::KakarotHintProcessor};
use alloy_genesis::Genesis;
use alloy_primitives::Address;
use cairo_vm::{
    air_private_input::AirPrivateInput,
    air_public_input::PublicInput,
    cairo_run::{cairo_run, CairoRunConfig},
    types::layout_name::LayoutName,
    vm::trace::trace_entry::RelocatedTraceEntry,
    Felt252,
};
use futures::StreamExt;
use once_cell::sync::Lazy;
use reth_chainspec::{ChainSpec, ChainSpecBuilder};
use reth_exex::{ExExContext, ExExEvent};
use reth_node_api::FullNodeComponents;
use reth_primitives::BlockNumHash;
use rusqlite::Connection;
use std::{path::PathBuf, sync::Arc};

/// The path to the SQLite database file.
pub const DATABASE_PATH: &str = "rollup.db";

/// The chain ID of the Kakarot Rollup chain.
const CHAIN_ID: u64 = 1;

/// The address of the rollup submitter (signer) to be funded with max coins.
const ROLLUP_SUBMITTER_ADDRESS: Address = Address::new([0; 20]);

/// The chain specification for the Kakarot Rollup chain.
///
/// Generated from the [`CHAIN_ID`] and [`ROLLUP_SUBMITTER_ADDRESS`] constants.
pub(crate) static CHAIN_SPEC: Lazy<Arc<ChainSpec>> = Lazy::new(|| {
    Arc::new(
        ChainSpecBuilder::default()
            .chain(CHAIN_ID.into())
            .genesis(Genesis::clique_genesis(CHAIN_ID, ROLLUP_SUBMITTER_ADDRESS))
            .cancun_activated()
            .build(),
    )
});

/// The Execution Extension for the Kakarot Rollup chain.
#[allow(missing_debug_implementations)]
pub struct KakarotRollup<Node: FullNodeComponents> {
    /// Capture the Execution Extension context.
    ctx: ExExContext<Node>,
    /// The SQLite database.
    db: Database,
}

impl<Node: FullNodeComponents> KakarotRollup<Node> {
    /// Creates a new instance of the [`KakarotRollup`] structure.
    pub fn new(ctx: ExExContext<Node>, connection: Connection) -> eyre::Result<Self> {
        Ok(Self { ctx, db: Database::new(connection)? })
    }

    /// Starts processing chain state notifications.
    pub async fn start(mut self) -> eyre::Result<()> {
        // Initialize the Cairo run configuration
        let config = CairoRunConfig {
            layout: LayoutName::all_cairo,
            trace_enabled: true,
            relocate_mem: true,
            proof_mode: true,
            ..Default::default()
        };

        // Process all new chain state notifications
        while let Some(notification) = self.ctx.notifications.next().await {
            // Check if the notification contains a committed chain.
            if let Some(committed_chain) = notification.committed_chain() {
                // Get the tip of the committed chain.
                let tip = committed_chain.tip();

                // Send a notification that the chain processing is finished.
                //
                // Finished height is the tip of the committed chain.
                //
                // The ExEx will not require all earlier blocks which can be pruned.
                self.ctx
                    .events
                    .send(ExExEvent::FinishedHeight(BlockNumHash::new(tip.number, tip.hash())))?;

                // Build the Kakarot hint processor.
                let mut hint_processor = KakarotHintProcessor::default().build();

                // Load the cairo program from the file
                let program = std::fs::read(PathBuf::from("../../cairo/programs/os.json"))?;

                // Execute the Kakarot os program
                let mut res = cairo_run(&program, &config, &mut hint_processor)?;

                // Retrieve the output of the program
                let mut output_buffer = String::new();
                res.vm.write_output(&mut output_buffer).unwrap();
                println!("Program output: \n{}", output_buffer);

                // Extract the execution trace
                let trace = res.relocated_trace.clone().unwrap_or_default();

                // Extract the relocated memory
                let memory = res
                    .relocated_memory
                    .clone()
                    .into_iter()
                    .map(|x| x.unwrap_or_default())
                    .collect();

                // Extract the public and private inputs
                //
                // We want to store the public input in the database in order to use them to run
                // the prover
                let public_input = res.get_air_public_input()?;
                let private_input = res.get_air_private_input();

                // Commit the execution trace to the database
                self.commit_cairo_execution_traces(
                    committed_chain.tip().number,
                    trace,
                    memory,
                    public_input,
                    private_input,
                )?;
            }
        }

        Ok(())
    }

    /// Commits the execution traces to the database.
    fn commit_cairo_execution_traces(
        &mut self,
        number: u64,
        trace: Vec<RelocatedTraceEntry>,
        memory: Vec<Felt252>,
        air_public_input: PublicInput<'_>,
        air_private_input: AirPrivateInput,
    ) -> eyre::Result<()> {
        self.db.insert_execution_trace(number, trace, memory, air_public_input, air_private_input)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use reth_execution_types::{Chain, ExecutionOutcome};
    use reth_exex_test_utils::{test_exex_context, PollOnce};
    use reth_primitives::{
        address, constants::ETH_TO_WEI, hex, Bytes, Header, Receipt, Receipts, SealedBlock,
        SealedBlockWithSenders, TransactionSigned, TxEip1559, B256, U256,
    };
    use reth_revm::primitives::AccountInfo;
    use std::{future::Future, pin::pin, str::FromStr};

    /// The initialization logic of the ExEx is just an async function.
    ///
    /// During initialization you can wait for resources you need to be up for the ExEx to function,
    /// like a database connection.
    async fn exex_init<Node: FullNodeComponents>(
        ctx: ExExContext<Node>,
    ) -> eyre::Result<impl Future<Output = eyre::Result<()>>> {
        // Open the SQLite database connection.
        let connection = Connection::open(DATABASE_PATH)?;

        // Initialize the database with the connection.
        let db = Database::new(connection)?;

        // Create a sender address for testing
        //
        // We want to fund artificially this address with some ETH because this is the address used
        // to send funds in the test transaction.
        let sender_address = address!("6a3cA5811d2c185E6e441cEFa771824fb355f9Ec");

        // Deposit some ETH to the sender and insert it into database
        db.set_account(
            sender_address,
            AccountInfo { balance: U256::from(ETH_TO_WEI), nonce: 0, ..Default::default() },
        )?;

        // Create the Kakarot Rollup chain instance and start processing chain state notifications.
        Ok(KakarotRollup { ctx, db }.start())
    }

    #[ignore = "block_header not implemented"]
    #[tokio::test]
    async fn test_exex() -> eyre::Result<()> {
        // Initialize the tracing subscriber for testing
        reth_tracing::init_test_tracing();

        // Remove the database file if it exists so we start with a clean db
        std::fs::remove_file(DATABASE_PATH).ok();

        // Initialize a test Execution Extension context with all dependencies
        let (ctx, mut handle) = test_exex_context().await?;

        // Random mainnet tx <https://etherscan.io/tx/0xc3099e296bc0eaa6d3a5e0f46fcc4a9bb2f42fb4668a17dd926d75ca651509f0>
        let tx = TransactionSigned {
            hash: B256::from_str(
                "0xc3099e296bc0eaa6d3a5e0f46fcc4a9bb2f42fb4668a17dd926d75ca651509f0",
            )
            .unwrap(),
            signature: reth_primitives::Signature {
                r: U256::from_str(
                    "0xe74ec6b1365234a0ebe63f8e238d2318b28d1d2c58ada3a153ad364497dac715",
                )
                .unwrap(),
                s: U256::from_str(
                    "0x7306a7cab3679ead15daee428d2481b1b92a5dc2303adfe4b3bbbb4713be74af",
                )
                .unwrap(),
                odd_y_parity: false,
            },
            transaction: reth_primitives::Transaction::Eip1559(TxEip1559 {
                chain_id: 1,
                nonce: 0,
                gas_limit: 0x3173e,
                max_fee_per_gas: 0x2a9860004,
                max_priority_fee_per_gas: 0x4903a597,
                to: reth_primitives::TxKind::Call(
                    Address::from_str("0xf3de3c0d654fda23dad170f0f320a92172509127").unwrap(),
                ),
                value: U256::from_str("0xb1a2bc2ec50000").unwrap(),
                access_list: Default::default(),
                input: Bytes::from_str("0x9871efa4000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b1a2bc2ec50000000000000000000000000000000000000000000000000009f7051a01fa559ee400000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000001b0000000000000003b6d0340cab7ab9f1a9add91380a0e8fae700b65f320e667").unwrap(),
            }),
        };

        // https://etherscan.io/block/15867168 where transaction root and receipts root are cleared
        // empty merkle tree: 0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421
        let header = Header {
            parent_hash: hex!("859fad46e75d9be177c2584843501f2270c7e5231711e90848290d12d7c6dcdd").into(),
            ommers_hash: hex!("1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347").into(),
            beneficiary: hex!("4675c7e5baafbffbca748158becba61ef3b0a263").into(),
            state_root: hex!("8337403406e368b3e40411138f4868f79f6d835825d55fd0c2f6e17b1a3948e9").into(),
            transactions_root: hex!("56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421").into(),
            receipts_root: hex!("56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421").into(),
            logs_bloom: hex!("002400000000004000220000800002000000000000000000000000000000100000000000000000100000000000000021020000000800000006000000002100040000000c0004000000000008000008200000000000000000000000008000000001040000020000020000002000000800000002000020000000022010000000000000010002001000000000020200000000000001000200880000004000000900020000000000020000000040000000000000000000000000000080000000000001000002000000000000012000200020000000000000001000000000000020000010321400000000100000000000000000000000000000400000000000000000").into(),
            difficulty: U256::ZERO, // total difficulty: 0xc70d815d562d3cfa955).into(),
            number: 0xf21d20,
            gas_limit: 0x1c9c380,
            gas_used: 0x6e813,
            timestamp: 0x635f9657,
            extra_data: hex!("")[..].into(),
            mix_hash: hex!("0000000000000000000000000000000000000000000000000000000000000000").into(),
            nonce: 0x0000000000000000,
            base_fee_per_gas: 0x28f0001df.into(),
            withdrawals_root: None,
            blob_gas_used: None,
            excess_blob_gas: None,
            parent_beacon_block_root: None,
            requests_root: None
        };

        // Create a sealed block with a single transaction
        let block = SealedBlockWithSenders {
            block: SealedBlock { header: header.seal_slow(), body: vec![tx], ..Default::default() },
            senders: vec![address!("6a3cA5811d2c185E6e441cEFa771824fb355f9Ec")],
        };

        // Create a Receipts object with a vector of receipt vectors
        let receipts = Receipts { receipt_vec: vec![vec![Some(Receipt::default())]] };

        // Send a notification to the Execution Extension that the chain has been committed
        handle
            .send_notification_chain_committed(Chain::from_block(
                block.clone(),
                ExecutionOutcome { receipts, first_block: 0xf21d20, ..Default::default() },
                None,
            ))
            .await?;

        // Initialize the Execution Extension
        let mut exex = pin!(exex_init(ctx).await?);

        // Check that the Execution Extension did not emit any events until we polled it
        handle.assert_events_empty();

        // Poll the Execution Extension once to process incoming notifications
        exex.poll_once().await?;

        // Check that the Execution Extension emitted a `FinishedHeight` event with the correct
        // height
        handle.assert_event_finished_height(0xf21d20)?;

        // Open the SQLite database connection.
        let connection = Connection::open(DATABASE_PATH)?;

        // Initialize the database with the connection.
        let db = Database::new(connection)?;

        // Check that the block has been inserted into the database
        assert_eq!(db.block(U256::from(0xf21d20))?.unwrap(), block);

        // Check that the execution trace has been inserted into the database
        assert!(db.execution_trace(0xf21d20)?.is_some());

        Ok(())
    }
}
