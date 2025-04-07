use clap::Parser;
use pyo3::prelude::*;
use std::path::PathBuf;

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
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
    #[arg(long, value_name = "FILE")]
    proof_path: Option<PathBuf>,

    /// Verify the Stwo proof after generation (only used with --stwo-proof)
    #[arg(long)]
    verify: bool,
}

fn main() -> PyResult<()> {
    let args = Args::parse();

    if !args.compiled_program.exists() {
        eprintln!("Error: Compiled program not found: {}", args.compiled_program.display());
        std::process::exit(1);
    }

    let zkpi_path = args.data_dir.join(format!("{}.json", args.block_number));
    if !zkpi_path.exists() {
        eprintln!("Error: ZKPI data not found: {}", zkpi_path.display());
        std::process::exit(1);
    }

    if !args.output_dir.exists() {
        std::fs::create_dir_all(&args.output_dir)
            .map_err(|e| {
                eprintln!("Error creating output directory: {e}");
                std::process::exit(1);
            })
            .unwrap();
    }

    Python::with_gil(|py| -> PyResult<()> {
        // Get the current directory and add it to Python's path
        let current_dir = std::env::current_dir()?;
        // Add the cairo directory to Python's path
        let sys = PyModule::import(py, "sys")?;
        let path = sys.getattr("path")?;
        path.call_method1("append", (current_dir.to_str().unwrap(),))?;

        let prove_block_module = PyModule::import(py, "cairo.scripts.prove_block")?;
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
    })
}
