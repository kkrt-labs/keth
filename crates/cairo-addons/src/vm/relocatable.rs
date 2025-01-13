use cairo_vm::types::relocatable::{
    MaybeRelocatable as RustMaybeRelocatable, Relocatable as RustRelocatable,
};
use pyo3::prelude::*;

use super::maybe_relocatable::PyMaybeRelocatable;

#[pyclass(name = "Relocatable")]
#[derive(Clone, Eq, PartialEq, Hash)]
pub struct PyRelocatable {
    pub(crate) inner: RustRelocatable,
}

#[derive(FromPyObject)]
enum PyRelocatableSub {
    #[pyo3(transparent)]
    Relocatable(PyRelocatable),
    #[pyo3(transparent)]
    Int(usize),
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

    fn __sub__(&self, other: PyRelocatableSub) -> PyResult<PyMaybeRelocatable> {
        match other {
            PyRelocatableSub::Int(x) => {
                let result = (self.inner - x)
                    .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;
                Ok(PyMaybeRelocatable::from(RustMaybeRelocatable::from(result)))
            }
            PyRelocatableSub::Relocatable(x) => {
                let result = (self.inner - x.inner)
                    .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;
                Ok(PyMaybeRelocatable::from(RustMaybeRelocatable::from(result)))
            }
        }
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
