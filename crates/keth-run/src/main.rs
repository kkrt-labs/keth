use pyo3::prelude::*;

const OUTPUT_DIR: &str = "output";
const DATA_DIR: &str = "data/1/eels";
const COMPILED_PROGRAM: &str = "build/main_compiled.json";
const BLOCK_NUMBER: u64 = 21922904; // 500M steps

fn main() -> PyResult<()> {
    Python::with_gil(|py| -> PyResult<()> {
        let current_dir = std::env::current_dir()?;
        let sys = PyModule::import(py, "sys")?;
        let path = sys.getattr("path")?;
        path.call_method1("append", (current_dir.to_str().unwrap(),))?;

        /*
        let module = PyModule::import(py, "cairo_addons.compiler")?;
        let test_value = module.getattr("TEST")?;
        println!("TEST value: {}", test_value);
        */

        println!("Starting proof mode");
        let zkpi_path = format!("{DATA_DIR}/{BLOCK_NUMBER}.json");
        let prove_block_module = PyModule::import(py, "cairo.scripts.prove_block")?;
        let load_zkpi_fixture = prove_block_module.getattr("load_zkpi_fixture")?;
        let program_inputs = load_zkpi_fixture.call1((zkpi_path,))?;

        // Convert PyObject to serde_json::Value
        // let program_inputs_json: serde_json::Value = program_inputs.extract(py)?;

        // Call the Rust version of run_proof_mode
        println!("Calling Rust run_proof_mode");
        cairo_addons_lib::run_proof_mode(
            "main".to_string(),
            program_inputs.into(),
            COMPILED_PROGRAM.to_string(),
            OUTPUT_DIR.into(),
            false,
            None,
            false,
        )
        .expect("Failed to run proof mode");
        println!("Rust run_proof_mode done");

        Ok(())
    })
}
