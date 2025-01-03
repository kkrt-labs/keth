use cairo_vm::vm::runners::cairo_runner::{ResourceTracker, RunResources};
use pyo3::prelude::*;

#[pyclass(name = "RunResources")]
#[derive(Clone)]
pub struct PyRunResources {
    pub(crate) inner: RunResources,
}

#[pymethods]
impl PyRunResources {
    #[new]
    #[pyo3(signature = (n_steps=None))]
    fn new(n_steps: Option<usize>) -> PyResult<Self> {
        match n_steps {
            Some(n_steps) => Ok(Self { inner: RunResources::new(n_steps) }),
            None => Ok(Self { inner: RunResources::default() }),
        }
    }

    #[getter]
    fn n_steps(&self) -> Option<usize> {
        self.inner.get_n_steps()
    }
}

impl From<RunResources> for PyRunResources {
    fn from(inner: RunResources) -> Self {
        Self { inner }
    }
}
