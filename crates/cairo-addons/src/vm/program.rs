use cairo_vm::{
    serde::deserialize_program::{deserialize_program_json, parse_program_json, ProgramJson},
    types::program::Program as RustProgram,
    Felt252,
};
use pyo3::prelude::*;

use crate::vm::builtins::PyBuiltinList;

use super::maybe_relocatable::PyMaybeRelocatable;

#[pyclass(name = "Program")]
pub struct PyProgram {
    pub(crate) inner: RustProgram,
}

#[pymethods]
impl PyProgram {
    #[staticmethod]
    #[pyo3(signature = (program_bytes, entrypoint=None))]
    fn from_bytes(program_bytes: &[u8], entrypoint: Option<&str>) -> PyResult<Self> {
        let mut program_json: ProgramJson = deserialize_program_json(program_bytes)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        // Manually add proof-mode instructions jmp rel 0 to be able to loop in proof mode and avoid
        // the proof-mode at compile time
        program_json.data.push(Felt252::from(0x10780017FFF7FFF_u64).into());
        program_json.data.push(Felt252::from(0).into());
        let program = parse_program_json(program_json, entrypoint)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(Self { inner: program })
    }

    #[getter]
    fn builtins(&self) -> Vec<String> {
        self.inner
            .builtins
            .iter()
            .map(|x| x.to_string().strip_suffix("_builtin").unwrap().to_string())
            .collect()
    }

    #[setter]
    fn set_builtins(&mut self, builtins: PyBuiltinList) -> PyResult<()> {
        self.inner.builtins = builtins
            .into_builtin_names()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }

    #[getter]
    fn data_length(&self) -> usize {
        self.inner.shared_program_data.data.len()
    }

    #[getter]
    fn data(&self) -> Vec<PyMaybeRelocatable> {
        self.inner.shared_program_data.data.iter().map(|x| x.clone().into()).collect()
    }
}
