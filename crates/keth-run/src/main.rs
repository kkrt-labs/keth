use clap::Parser;
use pyo3::prelude::*;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command()]
struct Args {
    /// Block number to prove (must be after Cancun fork)
    #[arg(value_name = "BLOCK_NUMBER")]
    block_number: u64,

    /// Directory to save proof artifacts
    #[arg(long, value_name = "DIR", default_value = "output")]
    output_dir: PathBuf,

    /// Directory containing ZKPI JSON files
    #[arg(long, value_name = "DIR", default_value = "data/1/eels")]
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

// Check if the PYTHONPATH, PYTHONHOME, and PYO3_PYTHON variables are set, panics if any one is
// missing
fn check_env() {
    dotenvy::dotenv().expect("Failed to load .env file");

    dotenvy::var("PYTHONPATH").expect("PYTHONPATH environment variable not set");
    dotenvy::var("PYTHONHOME").expect("PYTHONHOME environment variable not set");
    dotenvy::var("PYO3_PYTHON").expect("PYO3_PYTHON environment variable not set");
}

fn main() {
    check_env();

    let args = Args::parse();

    if !args.compiled_program.exists() {
        panic!("Compiled program not found: {}", args.compiled_program.display());
    }

    let zkpi_path = args.data_dir.join(format!("{}.json", args.block_number));
    if !zkpi_path.exists() {
        panic!("ZKPI data not found: {}", zkpi_path.display());
    }

    if !args.output_dir.exists() {
        std::fs::create_dir_all(&args.output_dir).expect("Error creating output directory");
    }

    let _ = Python::with_gil(|py| -> PyResult<()> {
        let prove_block_module = py.import("cairo.scripts.prove_block")?;
        let load_zkpi_fixture = prove_block_module.getattr("load_zkpi_fixture")?;
        let program_inputs = load_zkpi_fixture.call1((zkpi_path.to_str().unwrap(),))?;

        let run_proof_mode = prove_block_module.getattr("run_proof_mode")?;
        run_proof_mode.call1((
            "main",
            program_inputs,
            args.compiled_program.to_str().unwrap(),
            args.output_dir.to_str().unwrap(),
            args.stwo_proof,
            args.proof_path.as_ref().map(|p| p.to_str().unwrap()),
            args.verify,
        ))?;

        Ok(())
    });
}
