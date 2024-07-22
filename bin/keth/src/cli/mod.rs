use clap::Parser;

#[derive(Debug, Parser)]
pub struct Cli {
    #[command(flatten)]
    log: LogArgs,
}

#[derive(Debug, Parser)]
pub struct LogArgs {
    #[clap(short, long, default_value = "info")]
    pub filter: String,
}
