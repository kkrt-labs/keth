use clap::Parser;
use kakarot_node::node::KakarotNode;
use keth::cli::Cli;
use reth_chainspec::ChainSpec;
use reth_cli_runner::CliRunner;
use reth_db::init_db;
use reth_node_builder::{NodeBuilder, NodeConfig};
use reth_node_core::args::RpcServerArgs;
use std::sync::Arc;

fn main() {
    let args = Cli::parse();
    args.log.init_tracing();

    let chain_args = args.chain;

    let chain_spec: ChainSpec = (&chain_args).into();
    let dev_args = (&chain_args).into();

    let config = NodeConfig::default()
        .with_chain(chain_spec)
        .with_rpc(RpcServerArgs::default().with_http())
        .with_dev(dev_args);

    let data_dir = config.datadir();
    let db_path = data_dir.db();

    tracing::info!(target: "kkrt::cli", ?db_path, "Starting DB");
    let database =
        Arc::new(init_db(db_path, config.db.database_args()).expect("failed to init db"));

    let builder = NodeBuilder::new(config).with_database(database);

    let runner = CliRunner::default();
    runner
        .run_command_until_exit(|ctx| async {
            let builder = builder.with_launch_context(ctx.task_executor);
            let handle = Box::pin(builder.launch_node(KakarotNode::default())).await?;
            handle.node_exit_future.await
        })
        .expect("failed to run command until exit");
}
