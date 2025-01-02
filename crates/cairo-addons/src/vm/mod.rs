use pyo3::prelude::*;

mod program;
mod relocatable;
mod runner;

use program::PyProgram;
use relocatable::{PyMaybeRelocatable, PyRelocatable};
use runner::PyCairoRunner;

#[pymodule]
fn vm(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<PyProgram>()?;
    module.add_class::<PyCairoRunner>()?;
    module.add_class::<PyRelocatable>()?;
    module.add_class::<PyMaybeRelocatable>()?;
    Ok(())
}
