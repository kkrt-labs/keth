use pyo3::prelude::*;

mod builtins;
mod felt;
mod maybe_relocatable;
mod memory_segments;
mod program;
mod relocatable;
mod relocated_trace;
mod run_resources;
mod runner;

use felt::PyFelt;
use memory_segments::PyMemorySegmentManager;
use program::PyProgram;
use relocatable::PyRelocatable;
use relocated_trace::PyRelocatedTraceEntry;
use run_resources::PyRunResources;
use runner::PyCairoRunner;

#[pymodule]
fn vm(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<PyProgram>()?;
    module.add_class::<PyCairoRunner>()?;
    module.add_class::<PyRelocatable>()?;
    module.add_class::<PyFelt>()?;
    module.add_class::<PyMemorySegmentManager>()?;
    module.add_class::<PyRunResources>()?;
    module.add_class::<PyRelocatedTraceEntry>()?;
    Ok(())
}
