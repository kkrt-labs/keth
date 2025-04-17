use pyo3::{
    prelude::*,
    pymodule,
    types::{PyModule, PyModuleMethods},
    wrap_pymodule, Bound,
};

mod stwo_bindings;
mod vm;

#[pymodule]
#[pyo3(name = "rust_bindings")]
fn rust_bindings(root_module: &Bound<'_, PyModule>) -> PyResult<()> {
    root_module.add_wrapped(wrap_pymodule!(stwo_bindings::stwo_bindings))?;
    root_module.add_wrapped(wrap_pymodule!(vm::vm))?;
    Ok(())
}
