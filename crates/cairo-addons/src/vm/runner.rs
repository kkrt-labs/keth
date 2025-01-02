use crate::vm::program::PyProgram;
use cairo_vm::{
    types::layout_name::LayoutName, vm::runners::cairo_runner::CairoRunner as RustCairoRunner,
};
use pyo3::prelude::*;

use crate::vm::relocatable::PyRelocatable;

#[pyclass(name = "CairoRunner", unsendable)]
pub struct PyCairoRunner {
    inner: RustCairoRunner,
}

#[pymethods]
impl PyCairoRunner {
    #[new]
    #[pyo3(signature = (program, layout="plain", proof_mode=false))]
    fn new(program: &PyProgram, layout: &str, proof_mode: bool) -> PyResult<Self> {
        let layout = match layout {
            "plain" => LayoutName::plain,
            "small" => LayoutName::small,
            "dex" => LayoutName::dex,
            "recursive" => LayoutName::recursive,
            "starknet" => LayoutName::starknet,
            "starknet_with_keccak" => LayoutName::starknet_with_keccak,
            "recursive_large_output" => LayoutName::recursive_large_output,
            "recursive_with_poseidon" => LayoutName::recursive_with_poseidon,
            "all_cairo" => LayoutName::all_cairo,
            "all_solidity" => LayoutName::all_solidity,
            _ => return Err(PyErr::new::<pyo3::exceptions::PyValueError, _>("Invalid layout name")),
        };

        let inner = RustCairoRunner::new(
            &program.inner,
            layout,
            None, // dynamic_layout_params
            proof_mode,
            true, // trace_enabled
        )
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        Ok(Self { inner })
    }

    #[pyo3(signature = (program_base=None))]
    fn initialize_segments(&mut self, program_base: Option<PyRelocatable>) {
        self.inner.initialize_segments(program_base.map(|x| x.inner));
    }

    #[getter]
    fn program_base(&self) -> Option<PyRelocatable> {
        self.inner.program_base.map(|x| PyRelocatable { inner: x })
    }

    #[pyo3(signature = (allow_missing_builtins))]
    fn initialize_builtins(&mut self, allow_missing_builtins: bool) -> PyResult<()> {
        self.inner
            .initialize_builtins(allow_missing_builtins)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))
    }
}
