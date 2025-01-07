use cairo_vm::vm::trace::trace_entry::RelocatedTraceEntry;
use pyo3::prelude::*;

#[pyclass(name = "RelocatedTraceEntry")]
pub struct PyRelocatedTraceEntry {
    inner: RelocatedTraceEntry,
}

#[pymethods]
impl PyRelocatedTraceEntry {
    #[getter]
    fn pc(&self) -> usize {
        self.inner.pc
    }
    #[getter]
    fn ap(&self) -> usize {
        self.inner.ap
    }
    #[getter]
    fn fp(&self) -> usize {
        self.inner.fp
    }
}

impl From<RelocatedTraceEntry> for PyRelocatedTraceEntry {
    fn from(inner: RelocatedTraceEntry) -> Self {
        Self { inner }
    }
}
