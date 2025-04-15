use cairo_vm::{
    serde::deserialize_program::{
        deserialize_program_json, parse_program_json, HintParams, ProgramJson,
    },
    types::program::{Program as RustProgram, SharedProgramData},
    Felt252,
};
use pyo3::prelude::*;
use std::sync::Arc;

use crate::vm::builtins::PyBuiltinList;

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

    /// Replaces the `hint` with the `new_hint` in the program.
    /// Returns the original hint that can be restored later upon cleanup.
    ///
    /// Args:
    ///     hint_code: The hint code to replace.
    ///     new_hint_code: The new hint code to use.
    fn replace_hints(&mut self, hint_code: &str, new_hint_code: &str) -> PyResult<()> {
        let shared_data_ptr =
            Arc::as_ptr(&self.inner.shared_program_data) as *mut SharedProgramData;
        unsafe {
            let shared_data = &mut *shared_data_ptr;
            shared_data.hints_collection.hints.iter_mut().for_each(|hint| {
                if hint.code == hint_code {
                    hint.code = new_hint_code.to_string();
                }
            });
        }
        Ok(())
    }
}
