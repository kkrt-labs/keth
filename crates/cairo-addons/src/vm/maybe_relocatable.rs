use crate::vm::relocatable::PyRelocatable;
use cairo_vm::types::relocatable::MaybeRelocatable as RustMaybeRelocatable;
use num_bigint::BigUint;
use pyo3::{Bound, FromPyObject, IntoPyObject, IntoPyObjectExt, PyAny, Python};

#[derive(FromPyObject, Eq, PartialEq, Hash, Debug, Clone)]
pub enum PyMaybeRelocatable {
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
            RustMaybeRelocatable::Int(x) => PyMaybeRelocatable::BigUInt(x.to_biguint()),
            RustMaybeRelocatable::RelocatableValue(r) => PyMaybeRelocatable::Relocatable(r.into()),
        }
    }
}

impl From<PyMaybeRelocatable> for RustMaybeRelocatable {
    fn from(value: PyMaybeRelocatable) -> Self {
        match value {
            PyMaybeRelocatable::Int(x) => RustMaybeRelocatable::Int(x.into()),
            PyMaybeRelocatable::Relocatable(r) => RustMaybeRelocatable::RelocatableValue(r.inner),
            PyMaybeRelocatable::BigUInt(x) => RustMaybeRelocatable::Int(x.into()),
        }
    }
}

impl<'py> IntoPyObject<'py> for PyMaybeRelocatable {
    type Target = PyAny;
    type Output = Bound<'py, Self::Target>;
    type Error = std::convert::Infallible;

    fn into_pyobject(self, py: Python<'py>) -> Result<Self::Output, Self::Error> {
        let res = match self {
            PyMaybeRelocatable::Relocatable(r) => r.into_bound_py_any(py),
            PyMaybeRelocatable::Int(x) => x.into_bound_py_any(py),
            PyMaybeRelocatable::BigUInt(x) => x.into_bound_py_any(py),
        };

        Ok(res.unwrap())
    }
}
