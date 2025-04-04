use pyo3::prelude::*;

mod builtins;
mod dict_manager;
mod layout;
mod maybe_relocatable;
mod memory_segments;
mod program;
mod relocatable;
mod relocated_trace;
mod run_resources;
mod runner;
mod stripped_program;
mod vm_consts;

pub use cairo_addons_lib::vm::{Hint, HintCollection, HintProcessor};

use dict_manager::{PyDictManager, PyDictTracker};
use memory_segments::PyMemorySegmentManager;
use program::PyProgram;
use relocatable::PyRelocatable;
use relocated_trace::PyRelocatedTraceEntry;
use run_resources::PyRunResources;
use runner::{run_proof_mode, PyCairoRunner};
use stripped_program::PyStrippedProgram;
use vm_consts::{PyVmConst, PyVmConstsDict};

#[pymodule]
fn vm(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<PyProgram>()?;
    module.add_class::<PyCairoRunner>()?;
    module.add_class::<PyRelocatable>()?;
    module.add_class::<PyMemorySegmentManager>()?;
    module.add_class::<PyRunResources>()?;
    module.add_class::<PyRelocatedTraceEntry>()?;
    module.add_class::<PyStrippedProgram>()?;
    module.add_class::<PyDictManager>()?;
    module.add_class::<PyDictTracker>()?;
    module.add_function(wrap_pyfunction!(run_proof_mode, module)?)?;
    module.add_class::<PyVmConst>()?;
    module.add_class::<PyVmConstsDict>()?;
    Ok(())
}
