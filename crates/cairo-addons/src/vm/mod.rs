use pyo3::prelude::*;

mod builtins;
mod dict_manager;
mod felt;
mod hints;
mod layout;
mod maybe_relocatable;
mod memory_segments;
mod program;
mod relocatable;
mod relocated_trace;
mod run_resources;
mod runner;
mod stripped_program;

use dict_manager::{PyDictManager, PyDictTracker};
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
    module.add_class::<PyDictManager>()?;
    module.add_class::<PyDictTracker>()?;
    Ok(())
}
