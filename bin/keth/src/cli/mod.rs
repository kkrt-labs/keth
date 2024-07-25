use clap::Parser;
use reth_chainspec::{Chain, ChainSpec};
use reth_node_core::args::DevArgs;
use reth_primitives::{Address, Genesis};
use std::{str::FromStr, time::Duration};
use tracing_subscriber::EnvFilter;

#[derive(Debug, Parser)]
pub struct Cli {
    #[command(flatten)]
    pub chain: ChainArgs,
    #[command(flatten)]
    pub log: LogArgs,
}

#[derive(Debug, Parser)]
pub struct LogArgs {
    #[clap(short, long, default_value = "info")]
    pub filter: String,
}

impl LogArgs {
    pub fn init_tracing(&self) {
        let filter = EnvFilter::builder().parse(&self.filter).expect("failed to parse filter");
        tracing_subscriber::fmt().with_env_filter(filter).init();
    }
}

#[derive(Debug, Parser)]
pub struct ChainArgs {
    #[clap(short, long, default_value = "1802203764")]
    pub id: u64,
    #[clap(short, long, default_value = "12")]
    pub block_time: u64,
}

impl From<&ChainArgs> for ChainSpec {
    fn from(args: &ChainArgs) -> Self {
        let chain_id = args.id;
        ChainSpec::builder()
            .cancun_activated()
            .chain(Chain::from_id(chain_id))
            .genesis(Genesis::clique_genesis(
                chain_id,
                Address::from_str("0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266").unwrap(),
            ))
            .build()
    }
}

impl From<&ChainArgs> for DevArgs {
    fn from(args: &ChainArgs) -> Self {
        DevArgs {
            dev: true,
            block_time: Some(Duration::from_secs(args.block_time)),
            ..Default::default()
        }
    }
}
