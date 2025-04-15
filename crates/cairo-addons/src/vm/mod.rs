use pyo3::prelude::*;

mod builtins;
mod dict_manager;
mod hint_definitions;
mod hint_loader;
mod hint_utils;
mod hints;
mod layout;
mod maybe_relocatable;
mod memory_segments;
mod mod_builtin_runner;
mod poseidon_hash;
mod program;
mod pythonic_hint;
mod relocatable;
mod relocated_trace;
mod run_resources;
mod runner;
mod stripped_program;
mod vm_consts;

// Re-export the dynamic hint functionality

use dict_manager::{PyDictManager, PyDictTracker};
use memory_segments::PyMemorySegmentManager;
use mod_builtin_runner::PyModBuiltinRunner;
use program::PyProgram;
use relocatable::PyRelocatable;
use relocated_trace::PyRelocatedTraceEntry;
use run_resources::PyRunResources;
use runner::PyCairoRunner;
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
    module.add_function(wrap_pyfunction!(runner::run_proof_mode, module)?).unwrap();
    module.add_class::<PyVmConst>()?;
    module.add_class::<PyVmConstsDict>()?;
    module.add_class::<PyModBuiltinRunner>()?;
    module.add_function(wrap_pyfunction!(poseidon_hash::poseidon_hash_many, module)?).unwrap();
    Ok(())
}
