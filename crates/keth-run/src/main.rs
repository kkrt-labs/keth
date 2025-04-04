use pyo3::prelude::*;

const OUTPUT_DIR: &str = "output";
const DATA_DIR: &str = "data/1/eels";
const COMPILED_PROGRAM: &str = "build/main_compiled.json";
const BLOCK_NUMBER: u64 = 21922904; // 500M steps
fn main() -> PyResult<()> {
    Python::with_gil(|py| -> PyResult<()> {
        // Get the current directory and add it to Python's path
        let current_dir = std::env::current_dir()?;
        // Add the cairo directory to Python's path
        let sys = PyModule::import(py, "sys")?;
        let path = sys.getattr("path")?;
        path.call_method1("append", (current_dir.to_str().unwrap(),))?;

        /*
        let module = PyModule::import(py, "cairo_addons.compiler")?;
        let test_value = module.getattr("TEST")?;
        println!("TEST value: {}", test_value);
        */

        let zkpi_path = format!("{DATA_DIR}/{BLOCK_NUMBER}.json");
        let prove_block_module = PyModule::import(py, "cairo.scripts.prove_block")?;
        let load_zkpi_fixture = prove_block_module.getattr("load_zkpi_fixture")?;
        let program_inputs = load_zkpi_fixture.call1((zkpi_path,))?;

        let run_proof_mode = prove_block_module.getattr("run_proof_mode")?;
        println!("calling run_proof_mode");

        run_proof_mode.call1((
            "main",
            program_inputs,
            COMPILED_PROGRAM,
            OUTPUT_DIR,
            false,
            None::<&str>,
            false,
        ))?;
        println!("run_proof_mode done");

        Ok(())
    })
}
