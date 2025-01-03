use crate::vm::{builtins::PyBuiltinList, maybe_relocatable::PyMaybeRelocatable};
use cairo_vm::vm::runners::cairo_pie::StrippedProgram;
use pyo3::prelude::*;

#[pyclass(name = "StrippedProgram")]
#[derive(Clone)]
pub struct PyStrippedProgram {
    pub(crate) inner: StrippedProgram,
}

#[pymethods]
impl PyStrippedProgram {
    #[new]
    fn new(data: Vec<PyMaybeRelocatable>, builtins: PyBuiltinList, main: usize) -> PyResult<Self> {
        let data = data.into_iter().map(|x| x.into()).collect();
        let builtins = builtins.into_builtin_names()?;

        Ok(Self { inner: StrippedProgram { data, builtins, main, prime: () } })
    }

    #[getter]
    fn data(&self) -> Vec<PyMaybeRelocatable> {
        self.inner.data.iter().map(|x| x.clone().into()).collect()
    }

    #[getter]
    fn builtins(&self) -> Vec<String> {
        self.inner
            .builtins
            .iter()
            .map(|x| x.to_string().strip_suffix("_builtin").unwrap().to_string())
            .collect()
    }

    #[setter]
    fn set_builtins(&mut self, builtins: PyBuiltinList) -> PyResult<()> {
        self.inner.builtins = builtins.into_builtin_names()?;
        Ok(())
    }

    #[getter]
    fn main(&self) -> usize {
        self.inner.main
    }

    #[setter]
    fn set_main(&mut self, main: usize) {
        self.inner.main = main;
    }
}
