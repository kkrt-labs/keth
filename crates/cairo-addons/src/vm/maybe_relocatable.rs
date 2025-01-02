use cairo_vm::types::relocatable::MaybeRelocatable as RustMaybeRelocatable;
use pyo3::FromPyObject;

use crate::vm::{felt::Felt252Input, relocatable::PyRelocatable};

#[derive(FromPyObject)]
pub enum PyMaybeRelocatable {
    #[pyo3(transparent)]
    Int(Felt252Input),
    #[pyo3(transparent)]
    Relocatable(PyRelocatable),
}

impl From<PyMaybeRelocatable> for RustMaybeRelocatable {
    fn from(value: PyMaybeRelocatable) -> Self {
        match value {
            PyMaybeRelocatable::Int(val) => {
                RustMaybeRelocatable::Int(val.into_felt252().expect("Invalid Felt252"))
            }
            PyMaybeRelocatable::Relocatable(rel) => {
                RustMaybeRelocatable::RelocatableValue(rel.inner)
            }
        }
    }
}
