use crate::{
    atlantic::{prover::ProverVersion, sharp::SharpSdk},
    hints::KakarotHintProcessor,
};
use alloy_eips::BlockNumHash;
use cairo_vm::{
    cairo_run::{cairo_run, CairoRunConfig},
    types::layout_name::LayoutName,
};
use futures::StreamExt;
use reth_exex::{ExExContext, ExExEvent};
use reth_node_api::FullNodeComponents;
use std::{
    fs,
    io::Read,
    path::{Path, PathBuf},
};

/// The Execution Extension for the Kakarot Rollup chain.
#[allow(missing_debug_implementations)]
pub struct KakarotRollup<Node: FullNodeComponents> {
    /// Capture the Execution Extension context.
    ctx: ExExContext<Node>,
}

impl<Node: FullNodeComponents> KakarotRollup<Node> {
    /// Creates a new instance of the [`KakarotRollup`] structure.
    pub const fn new(ctx: ExExContext<Node>) -> eyre::Result<Self> {
        Ok(Self { ctx })
    }

    /// Starts processing chain state notifications.
    pub async fn start(mut self, sharp_sdk: SharpSdk) -> eyre::Result<()> {
        // Initialize the Cairo run configuration
        let config = CairoRunConfig {
            layout: LayoutName::all_cairo,
            trace_enabled: true,
            relocate_mem: true,
            // proof_mode: true,
            ..Default::default()
        };

        // Process all new chain state notifications
        while let Some(notification) = self.ctx.notifications.next().await {
            // Check if the notification contains a committed chain.
            if let Some(committed_chain) = notification?.committed_chain() {
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
                let program = std::fs::read(PathBuf::from("../../cairo/programs/fibonacci.json"))?;

                // Execute the Kakarot os program
                let mut res = cairo_run(&program, &config, &mut hint_processor)?;

                let cairo_pie = res.get_cairo_pie().unwrap();

                // Path to a temporary file for the CairoPie.
                let temp_file_path = Path::new("temp_pie.zip");

                // Write the CairoPie data into a temporary file.
                cairo_pie.write_zip_file(temp_file_path)?;

                // Read the temporary file into a Vec<u8>.
                let mut file = fs::File::open(temp_file_path)?;
                let mut pie_bytes = Vec::new();
                file.read_to_end(&mut pie_bytes)?;

                // Remove the temporary file after reading.
                fs::remove_file(temp_file_path)?;

                // Call the proof generation function using the Sharp SDK.
                let _result =
                    sharp_sdk.proof_generation(pie_bytes, "auto", ProverVersion::Starkware).await;

                // Retrieve the output of the program
                let mut output_buffer = String::new();
                res.vm.write_output(&mut output_buffer).unwrap();
                println!("Program output: \n{output_buffer}");

                // Extract the execution trace
                let _trace = res.relocated_trace.clone().unwrap_or_default();

                // Extract the relocated memory
                let _memory = res
                    .relocated_memory
                    .clone()
                    .into_iter()
                    .map(Option::unwrap_or_default)
                    .collect::<Vec<_>>();

                // Extract the public and private inputs
                //
                // We want to store the public input in the database in order to use them to run
                // the prover
                let _public_input = res.get_air_public_input()?;
                let _private_input = res.get_air_private_input();
            }
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use crate::atlantic::sharp::SharpSdk;

    use super::*;
    use alloy_consensus::{Header, TxEip1559};
    use alloy_primitives::{address, hex, Address, Bytes, Sealable, B256, U256};
    use mockito::Server;
    use reth_execution_types::{Chain, ExecutionOutcome};
    use reth_exex_test_utils::test_exex_context;
    use reth_primitives::{
        BlockBody, Receipt, Receipts, SealedBlock, SealedBlockWithSenders, SealedHeader,
        TransactionSigned,
    };
    use std::{env, future::Future, str::FromStr, time::Duration};
    use tokio::time::timeout;
    use url::Url;

    /// The initialization logic of the Execution Extension is just an async function.
    ///
    /// During initialization you can wait for resources you need to be up for the Execution
    /// Extension to function, like a database connection.
    fn exex_init<Node: FullNodeComponents>(
        ctx: ExExContext<Node>,
        sharp_sdk: SharpSdk,
    ) -> impl Future<Output = eyre::Result<()>> {
        // Create the Kakarot Rollup chain instance and start processing chain state notifications.
        KakarotRollup { ctx }.start(sharp_sdk)
    }

    #[ignore = "block_header not implemented"]
    #[tokio::test]
    #[allow(clippy::too_many_lines)]
    async fn test_exex() -> eyre::Result<()> {
        // Initialize the tracing subscriber for testing
        reth_tracing::init_test_tracing();

        let mocked_api_key = "mocked_api_key";
        env::set_var("ATLANTIC_API_KEY", mocked_api_key);

        let mut server = Server::new_async().await;

        let proof_generation_mock = server
            .mock("POST", "/proof-generation")
            .match_query(mockito::Matcher::UrlEncoded(
                "apiKey".to_string(),
                mocked_api_key.to_string(),
            ))
            .match_body(mockito::Matcher::Any)
            .with_status(200)
            .with_body(
                r#"{
                       "atlanticQueryId": "mocked_query_id"
                   }"#,
            )
            .create_async()
            .await;

        let sharp_sdk =
            SharpSdk::new(mocked_api_key.to_string(), Url::parse(&server.url()).unwrap());

        drop(server);

        // Initialize a test Execution Extension context with all dependencies
        let (ctx, mut handle) = test_exex_context().await?;

        // Random mainnet tx <https://etherscan.io/tx/0xc3099e296bc0eaa6d3a5e0f46fcc4a9bb2f42fb4668a17dd926d75ca651509f0>
        let tx = TransactionSigned {
            hash: B256::from_str(
                "0xc3099e296bc0eaa6d3a5e0f46fcc4a9bb2f42fb4668a17dd926d75ca651509f0",
            )
            .unwrap(),
            signature:
            alloy_primitives::PrimitiveSignature::from_scalars_and_parity(B256::from_str(
                "0xe74ec6b1365234a0ebe63f8e238d2318b28d1d2c58ada3a153ad364497dac715",
            )
            .unwrap(), B256::from_str(
                "0x7306a7cab3679ead15daee428d2481b1b92a5dc2303adfe4b3bbbb4713be74af",
            )
            .unwrap(), false),
            transaction: reth_primitives::Transaction::Eip1559(TxEip1559 {
                chain_id: 1,
                nonce: 0,
                gas_limit: 0x3173e,
                max_fee_per_gas: 0x0002_a986_0004,
                max_priority_fee_per_gas: 0x4903_a597,
                to: alloy_primitives::TxKind::Call(
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
            number: 0x00f2_1d20,
            gas_limit: 0x01c9_c380,
            gas_used: 0x6e813,
            timestamp: 0x635f_9657,
            extra_data: hex!("")[..].into(),
            mix_hash: hex!("0000000000000000000000000000000000000000000000000000000000000000").into(),
            nonce: 0x0000_0000_0000_0000_u64.into(),
            base_fee_per_gas: 0x0002_8f00_01df.into(),
            withdrawals_root: None,
            blob_gas_used: None,
            excess_blob_gas: None,
            parent_beacon_block_root: None,
            requests_hash: None
        };

        let sealed_header = header.seal_slow();
        let (header, seal) = sealed_header.into_parts();

        // Create a sealed block with a single transaction
        let block = SealedBlockWithSenders {
            block: SealedBlock {
                header: SealedHeader::new(header, seal),
                body: BlockBody { transactions: vec![tx], ..Default::default() },
            },
            senders: vec![address!("6a3cA5811d2c185E6e441cEFa771824fb355f9Ec")],
        };

        // Create a Receipts object with a vector of receipt vectors
        let receipts = Receipts { receipt_vec: vec![vec![Some(Receipt::default())]] };

        // Send a notification to the Execution Extension that the chain has been committed
        handle
            .send_notification_chain_committed(Chain::from_block(
                block.clone(),
                ExecutionOutcome { receipts, first_block: 0x00f2_1d20, ..Default::default() },
                None,
            ))
            .await?;

        // Initialize the Execution Extension future
        let exex_future = exex_init(ctx, sharp_sdk);
        tokio::pin!(exex_future);

        // Set a timeout to stop infinite execution
        let timeout_duration = Duration::from_millis(100);
        let exex_result = timeout(timeout_duration, exex_future).await;

        match exex_result {
            Ok(Err(err)) => {
                eprintln!("Execution Extension returned an error: {err:?}");
                return Err(err);
            }
            _ => {
                println!("Execution Extension completed successfully.");
            }
        }

        // Check that the Execution Extension emitted a `FinishedHeight` event with the correct
        // height
        handle.assert_event_finished_height(BlockNumHash::new(0x00f2_1d20, seal))?;
        proof_generation_mock.assert();

        Ok(())
    }
}
