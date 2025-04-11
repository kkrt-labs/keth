use crate::vm::builtins::PyBuiltinList;
use cairo_vm::{
    serde::deserialize_program::{deserialize_program_json, parse_program_json, ProgramJson},
    types::program::Program as RustProgram,
    with_std::sync::Arc,
    Felt252,
};
use pyo3::prelude::*;

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

    /// Creates a new program with a specified hint code replaced by new hint code.
    ///
    /// This method clones the current program, searches for a hint matching `hint_code`
    /// in the program's hints list, replaces it with `new_hint_code`, and returns the
    /// modified program. If the specified hint is not found, it returns the original program.
    ///
    /// Args:
    ///     hint_identifier (String): The original hint code to replace.
    ///     hint_code (String): The new hint code to insert.
    ///
    /// Returns:
    ///     RustProgram: A new program with the hint patched, or the original program
    ///     if the hint is not found.
    #[pyo3(name = "program_with_patched_hint")]
    fn program_with_patched_hint(
        &self,
        hint_identifier: String,
        hint_code: String,
    ) -> PyResult<Self> {
        let program_with_patched_hint = self
            .inner
            .shared_program_data
            .hints_collection
            .iter_hints()
            .position(|hint| hint.code == hint_identifier)
            .map_or_else(
                || Ok(Self { inner: self.inner.clone() }),
                |hint_position| {
                    let mut cloned_program = self.inner.clone();
                    let mut new_shared_data = (*cloned_program.shared_program_data).clone();
                    let mut modified_hint =
                        cloned_program.shared_program_data.hints_collection.hints[hint_position]
                            .clone();
                    modified_hint.code = hint_code;
                    new_shared_data.hints_collection.hints[hint_position] = modified_hint;
                    cloned_program.shared_program_data = Arc::new(new_shared_data);

                    Ok(Self { inner: cloned_program })
                },
            );

        program_with_patched_hint
    }
}
