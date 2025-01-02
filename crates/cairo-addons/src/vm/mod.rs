use pyo3::prelude::*;

mod felt;
mod maybe_relocatable;
mod memory_segments;
mod program;
mod relocatable;
mod runner;

use felt::PyFelt;
use maybe_relocatable::PyMaybeRelocatable;
use memory_segments::PyMemorySegmentManager;
use program::PyProgram;
use relocatable::PyRelocatable;
use runner::PyCairoRunner;

#[pymodule]
fn vm(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<PyProgram>()?;
    module.add_class::<PyCairoRunner>()?;
    module.add_class::<PyRelocatable>()?;
    module.add_class::<PyMaybeRelocatable>()?;
    module.add_class::<PyFelt>()?;
    module.add_class::<PyMemorySegmentManager>()?;
    Ok(())
}
