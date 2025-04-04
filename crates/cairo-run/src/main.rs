use pyo3::prelude::*;
use std::env;

fn main() -> PyResult<()> {
    pyo3::prepare_freethreaded_python();
    Python::with_gil(|py| -> PyResult<()> {
        // Get the current directory and add it to Python's path
        let mut current_dir = env::current_dir()?;
        current_dir.push("python/cairo-addons/src/");
        let sys = PyModule::import(py, "sys")?;
        let path = sys.getattr("path")?;
        path.call_method1("append", (current_dir.to_str().unwrap(),))?;

        let module = PyModule::import(py, "cairo_addons.compiler")?;
        let test_value = module.getattr("TEST")?;
        println!("TEST value: {}", test_value);

        // let main_func = module.getattr("main")?;
        // main_func.call0()?;
        Ok(())
    })
}
