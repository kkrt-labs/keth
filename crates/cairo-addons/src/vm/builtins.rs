use cairo_vm::types::builtin_name::BuiltinName;
use pyo3::{prelude::*, FromPyObject};

#[derive(FromPyObject)]
pub struct PyBuiltinList(Vec<String>);

impl PyBuiltinList {
    pub fn into_builtin_names(self) -> PyResult<Vec<BuiltinName>> {
        self.0
            .into_iter()
            .map(|s| {
                BuiltinName::from_str(&s).ok_or_else(|| {
                    PyErr::new::<pyo3::exceptions::PyValueError, _>(format!(
                        "Invalid builtin name: {}",
                        s
                    ))
                })
            })
            .collect()
    }
}
