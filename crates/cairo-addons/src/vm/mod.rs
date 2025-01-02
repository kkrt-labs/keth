use pyo3::prelude::*;
mod program;
use program::PyProgram;

#[pymodule]
fn vm(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<PyProgram>()?;
    Ok(())
}
