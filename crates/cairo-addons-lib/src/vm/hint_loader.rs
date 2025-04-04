use pyo3::{prelude::*, types::PyDict};
use std::collections::HashMap;

pub fn load_python_hints() -> PyResult<HashMap<String, String>> {
    Python::with_gil(|py| {
        let hints_module = py.import("cairo_addons.hints")?;
        let impl_attr = hints_module.getattr("implementations")?;
        let implementations = impl_attr.downcast::<PyDict>()?;

        let mut hints = HashMap::new();
        for (key, value) in implementations.iter() {
            hints.insert(key.extract::<String>()?, value.extract::<String>()?);
        }

        Ok(hints)
    })
}
