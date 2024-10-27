use alloy_genesis::Genesis;
use alloy_primitives::Address;
use clap::{Parser, value_parser};
use reth_chainspec::{Chain, ChainSpec};
use reth_node_core::args::DevArgs;
use std::{str::FromStr, time::Duration};
use tracing_subscriber::EnvFilter;

const DEFAULT_CHAIN_ID: u64 = 1802203764;
const DEFAULT_BLOCK_TIME: u64 = 12;
const DEFAULT_ADDRESS: &str = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";

#[derive(Debug, Parser)]
pub struct Cli {
    #[command(flatten)]
    pub chain: ChainArgs,
    #[command(flatten)]
    pub log: LogArgs,
}

#[derive(Debug, Parser)]
pub struct LogArgs {
    /// Set the log filter level (e.g., debug, info, warn)
    #[clap(short, long, default_value = "info")]
    pub filter: String,
}

impl LogArgs {
    pub fn init_tracing(&self) {
        if let Ok(filter) = EnvFilter::builder().parse(&self.filter) {
            tracing_subscriber::fmt().with_env_filter(filter).init();
        } else {
            eprintln!("Warning: failed to parse log filter '{}'", &self.filter);
        }
    }
}

#[derive(Debug, Parser)]
pub struct ChainArgs {
    /// The chain ID for the chain specification
    #[clap(short, long, value_parser = value_parser!(u64), default_value_t = DEFAULT_CHAIN_ID)]
    pub id: u64,

    /// The block time for the chain in seconds
    #[clap(short, long, value_parser = value_parser!(u64), default_value_t = DEFAULT_BLOCK_TIME)]
    pub block_time: u64,
}

impl From<&ChainArgs> for ChainSpec {
    fn from(args: &ChainArgs) -> Self {
        let chain_id = args.id;
        let genesis_address = Address::from_str(DEFAULT_ADDRESS)
            .expect("DEFAULT_ADDRESS should be a valid Ethereum address");

        ChainSpec::builder()
            .cancun_activated()
            .chain(Chain::from_id(chain_id))
            .genesis(Genesis::clique_genesis(chain_id, genesis_address))
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
