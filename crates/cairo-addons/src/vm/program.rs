use cairo_vm::types::program::Program as RustProgram;
use pyo3::prelude::*;

#[pyclass(name = "Program")]
pub struct PyProgram {
    inner: RustProgram,
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
}
