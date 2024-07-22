use clap::Parser;
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
    #[clap(short, long, default_value = "1")]
    pub id: u64,
}
