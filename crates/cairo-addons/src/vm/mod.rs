use pyo3::prelude::*;

mod program;
mod runner;

use program::PyProgram;
use runner::PyCairoRunner;

#[pymodule]
fn vm(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<PyProgram>()?;
    module.add_class::<PyCairoRunner>()?;
    Ok(())
}
