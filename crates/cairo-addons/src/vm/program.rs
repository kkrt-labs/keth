use cairo_vm::types::program::Program as RustProgram;
use pyo3::prelude::*;

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
        let inner = RustProgram::from_bytes(program_bytes, entrypoint)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(Self { inner })
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
}
