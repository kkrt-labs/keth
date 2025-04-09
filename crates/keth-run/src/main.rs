use clap::Parser;
use pyo3::prelude::*;
use std::path::PathBuf;
const CANCUN_FORK: u64 = 19_426_588;

#[derive(Parser, Debug)]
#[command()]
struct Args {
    /// Block number to prove (must be after Cancun fork)
    #[arg(
        value_name = "BLOCK_NUMBER",
        value_parser = clap::value_parser!(u64).range(CANCUN_FORK..),
        help = "Block number (should be higher than Cancun fork (19426588))"
    )]
    block_number: u64,

    /// Directory to save proof artifacts
    #[arg(long, value_name = "DIR", default_value = "output")]
    output_dir: PathBuf,

    /// Directory containing ZKPI JSON files
    #[arg(long, value_name = "DIR", default_value = "data/inputs/1")]
    data_dir: PathBuf,

    /// Path to compiled Cairo program
    #[arg(long, value_name = "FILE", default_value = "build/main_compiled.json")]
    compiled_program: PathBuf,

    /// Generate Stwo proof instead of prover inputs
    #[arg(long)]
    stwo_proof: bool,

    /// Path to save the Stwo proof (required when --stwo-proof is used)
    #[arg(long, value_name = "FILE", required_if_eq("stwo_proof", "true"))]
    proof_path: Option<PathBuf>,

    /// Verify the Stwo proof after generation (only used with --stwo-proof)
    #[arg(long)]
    verify: bool,
}

fn main() {
    let args = Args::parse();

    dotenvy::dotenv().expect("Failed to load .env file");

    let zkpi_path = args.data_dir.join(format!("{}.json", args.block_number));

    let _ = Python::with_gil(|py| -> PyResult<()> {
        let prove_block_fn = py.import("scripts.prove_block")?.getattr("prove_block")?;
        prove_block_fn.call1((
            args.block_number,
            args.output_dir,
            zkpi_path,
            args.compiled_program,
            args.stwo_proof,
            args.proof_path,
            args.verify,
        ))?;

        Ok(())
    });
}
