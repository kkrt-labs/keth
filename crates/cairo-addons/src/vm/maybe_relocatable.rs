use cairo_vm::types::relocatable::MaybeRelocatable as RustMaybeRelocatable;
use pyo3::{FromPyObject, IntoPy, PyObject, Python};

use crate::vm::{felt::PyFelt, relocatable::PyRelocatable};

#[derive(FromPyObject)]
pub enum PyMaybeRelocatable {
    #[pyo3(transparent)]
    Int(PyFelt),
    #[pyo3(transparent)]
    Relocatable(PyRelocatable),
}

impl From<RustMaybeRelocatable> for PyMaybeRelocatable {
    fn from(value: RustMaybeRelocatable) -> Self {
        match value {
            RustMaybeRelocatable::Int(x) => PyMaybeRelocatable::Int(x.into()),
            RustMaybeRelocatable::RelocatableValue(r) => PyMaybeRelocatable::Relocatable(r.into()),
        }
    }
}

impl From<PyMaybeRelocatable> for RustMaybeRelocatable {
    fn from(value: PyMaybeRelocatable) -> Self {
        match value {
            PyMaybeRelocatable::Int(x) => RustMaybeRelocatable::Int(x.inner),
            PyMaybeRelocatable::Relocatable(r) => RustMaybeRelocatable::RelocatableValue(r.inner),
        }
    }
}

impl IntoPy<PyObject> for PyMaybeRelocatable {
    fn into_py(self, py: Python<'_>) -> PyObject {
        match self {
            PyMaybeRelocatable::Int(x) => x.into_py(py),
            PyMaybeRelocatable::Relocatable(r) => r.into_py(py),
        }
    }
}
