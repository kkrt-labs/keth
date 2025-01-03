use cairo_vm::types::relocatable::Relocatable as RustRelocatable;
use pyo3::prelude::*;

#[pyclass(name = "Relocatable")]
#[derive(Clone)]
pub struct PyRelocatable {
    pub(crate) inner: RustRelocatable,
}

#[pymethods]
impl PyRelocatable {
    #[new]
    fn new(segment_index: isize, offset: usize) -> Self {
        Self { inner: RustRelocatable::from((segment_index, offset)) }
    }

    #[getter]
    fn segment_index(&self) -> isize {
        self.inner.segment_index
    }

    #[getter]
    fn offset(&self) -> usize {
        self.inner.offset
    }

    fn __add__(&self, other: usize) -> PyResult<Self> {
        let result = (self.inner + other)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;
        Ok(Self { inner: result })
    }

    fn __sub__(&self, other: usize) -> PyResult<Self> {
        let result = (self.inner - other)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;
        Ok(Self { inner: result })
    }

    fn __eq__(&self, other: &PyRelocatable) -> bool {
        self.inner == other.inner
    }

    fn __str__(&self) -> String {
        format!("{}:{}", self.inner.segment_index, self.inner.offset)
    }

    fn __repr__(&self) -> String {
        format!(
            "Relocatable(segment_index={}, offset={})",
            self.inner.segment_index, self.inner.offset
        )
    }

    fn __lt__(&self, other: &PyRelocatable) -> bool {
        self.inner < other.inner
    }

    fn __le__(&self, other: &PyRelocatable) -> bool {
        self.inner <= other.inner
    }

    fn __gt__(&self, other: &PyRelocatable) -> bool {
        self.inner > other.inner
    }

    fn __ge__(&self, other: &PyRelocatable) -> bool {
        self.inner >= other.inner
    }

    fn __hash__(&self) -> PyResult<isize> {
        Ok(self.inner.segment_index ^ (self.inner.offset as isize))
    }
}

impl From<RustRelocatable> for PyRelocatable {
    fn from(rel: RustRelocatable) -> Self {
        Self { inner: rel }
    }
}
