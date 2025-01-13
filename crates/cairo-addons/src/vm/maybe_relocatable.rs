use crate::vm::{felt::PyFelt, relocatable::PyRelocatable};
use cairo_vm::types::relocatable::MaybeRelocatable as RustMaybeRelocatable;
use num_bigint::BigUint;
use pyo3::{FromPyObject, IntoPy, PyObject, Python};

#[derive(FromPyObject, Eq, PartialEq, Hash)]
pub enum PyMaybeRelocatable {
    #[pyo3(transparent)]
    Felt(PyFelt),
    #[pyo3(transparent)]
    Relocatable(PyRelocatable),
    #[pyo3(transparent)]
    Int(usize),
    #[pyo3(transparent)]
    BigUInt(BigUint),
}

impl From<RustMaybeRelocatable> for PyMaybeRelocatable {
    fn from(value: RustMaybeRelocatable) -> Self {
        match value {
            RustMaybeRelocatable::Int(x) => PyMaybeRelocatable::Felt(x.into()),
            RustMaybeRelocatable::RelocatableValue(r) => PyMaybeRelocatable::Relocatable(r.into()),
        }
    }
}

impl From<PyMaybeRelocatable> for RustMaybeRelocatable {
    fn from(value: PyMaybeRelocatable) -> Self {
        match value {
            PyMaybeRelocatable::Int(x) => RustMaybeRelocatable::Int(x.into()),
            PyMaybeRelocatable::Felt(x) => RustMaybeRelocatable::Int(x.inner),
            PyMaybeRelocatable::Relocatable(r) => RustMaybeRelocatable::RelocatableValue(r.inner),
            PyMaybeRelocatable::BigUInt(x) => RustMaybeRelocatable::Int(x.into()),
        }
    }
}

impl IntoPy<PyObject> for PyMaybeRelocatable {
    fn into_py(self, py: Python<'_>) -> PyObject {
        match self {
            PyMaybeRelocatable::Felt(x) => x.inner.to_biguint().into_py(py),
            PyMaybeRelocatable::Relocatable(r) => r.into_py(py),
            PyMaybeRelocatable::Int(x) => x.into_py(py),
            PyMaybeRelocatable::BigUInt(x) => x.into_py(py),
        }
    }
}
