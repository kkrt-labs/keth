use pyo3::prelude::*;
use pyo3::types::PyModule;
use pyo3::types::PyTuple;
use pyo3_ffi::c_str;

fn main() -> PyResult<()> {
    /*
    let program_inputs = Python::with_gil(|py| -> PyResult<Py<PyAny>> {
        let prove_block = PyModule::import(py, "prove_block")?;

        // Create an empty path string for testing
        let pathlib = PyModule::import(py, "pathlib")?;
        let path_class = pathlib.getattr("Path")?;
        let path = path_class.call1(("TODO",))?;
        
        // Call load_zkpi_fixture
        let result = prove_block.getattr("load_zkpi_fixture")?.call1((path,))?.into();
        Ok(result)
    })?;

    println!("Program inputs: {:?}", program_inputs);
    */


    // From https://pyo3.rs/v0.23.1/python-from-rust/function-calls.html#creating-keyword-arguments
    let arg1 = "arg1";
    let arg2 = "arg2";
    let arg3 = "arg3";

    Python::with_gil(|py| {
        let fun: Py<PyAny> = PyModule::from_code(
            py,
            c_str!("def example(*args, **kwargs):
                if args != ():
                    print('called with args', args)
                if kwargs != {}:
                    print('called with kwargs', kwargs)
                if args == () and kwargs == {}:
                    print('called with no arguments')"),
            c_str!(""),
            c_str!(""),
        )?
        .getattr("example")?
        .into();

        // call object without any arguments
        fun.call0(py)?;

        // pass object with Rust tuple of positional arguments
        let args = (arg1, arg2, arg3);
        fun.call1(py, args)?;

        // call object with Python tuple of positional arguments
        let args = PyTuple::new(py, &[arg1, arg2, arg3])?;
        fun.call1(py, args)?;
        Ok(())
    })
}
