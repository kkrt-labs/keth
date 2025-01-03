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
mod stripped_program;
use felt::PyFelt;
use memory_segments::PyMemorySegmentManager;
use program::PyProgram;
use relocatable::PyRelocatable;
use relocated_trace::PyRelocatedTraceEntry;
use run_resources::PyRunResources;
use runner::PyCairoRunner;
use stripped_program::PyStrippedProgram;

#[pymodule]
fn vm(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<PyProgram>()?;
    module.add_class::<PyCairoRunner>()?;
    module.add_class::<PyRelocatable>()?;
    module.add_class::<PyFelt>()?;
    module.add_class::<PyMemorySegmentManager>()?;
    module.add_class::<PyRunResources>()?;
    module.add_class::<PyRelocatedTraceEntry>()?;
    module.add_class::<PyStrippedProgram>()?;
    Ok(())
}
