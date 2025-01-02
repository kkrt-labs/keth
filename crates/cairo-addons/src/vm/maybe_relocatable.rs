use cairo_vm::types::relocatable::MaybeRelocatable as RustMaybeRelocatable;
use pyo3::prelude::*;

use crate::vm::{felt::Felt252Input, relocatable::PyRelocatable};

#[pyclass(name = "MaybeRelocatable")]
#[derive(Clone)]
pub struct PyMaybeRelocatable {
    pub(crate) inner: RustMaybeRelocatable,
}

#[pymethods]
impl PyMaybeRelocatable {
    #[new]
    #[pyo3(signature = (value=None, int_value=None))]
    fn new(value: Option<PyRelocatable>, int_value: Option<Felt252Input>) -> PyResult<Self> {
        match (value, int_value) {
            (Some(rel), None) => {
                Ok(Self { inner: RustMaybeRelocatable::RelocatableValue(rel.inner) })
            }
            (None, Some(val)) => {
                let felt = val.into_felt252()?;
                Ok(Self { inner: RustMaybeRelocatable::Int(felt) })
            }
            _ => Err(PyErr::new::<pyo3::exceptions::PyValueError, _>(
                "Must provide either relocatable or int value, not both or neither",
            )),
        }
    }

    fn __str__(&self) -> String {
        match &self.inner {
            RustMaybeRelocatable::Int(x) => x.to_string(),
            RustMaybeRelocatable::RelocatableValue(r) => {
                format!("{}:{}", r.segment_index, r.offset)
            }
        }
    }

    fn __repr__(&self) -> String {
        match &self.inner {
            RustMaybeRelocatable::Int(x) => format!("MaybeRelocatable({})", x),
            RustMaybeRelocatable::RelocatableValue(r) => {
                format!("MaybeRelocatable(segment_index={}, offset={})", r.segment_index, r.offset)
            }
        }
    }

    fn __hash__(&self) -> PyResult<isize> {
        match &self.inner {
            RustMaybeRelocatable::Int(x) => {
                Ok(x.to_bytes_be().iter().fold(0isize, |acc, &x| acc ^ (x as isize)))
            }
            RustMaybeRelocatable::RelocatableValue(r) => Ok(r.segment_index ^ (r.offset as isize)),
        }
    }
}

impl From<RustMaybeRelocatable> for PyMaybeRelocatable {
    fn from(rel: RustMaybeRelocatable) -> Self {
        Self { inner: rel }
    }
}
