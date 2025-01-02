use cairo_vm::{
    types::relocatable::{
        MaybeRelocatable as RustMaybeRelocatable, Relocatable as RustRelocatable,
    },
    Felt252,
};
use pyo3::{prelude::*, FromPyObject};

#[derive(FromPyObject)]
enum Felt252Input {
    #[pyo3(transparent)]
    Int(PyObject),
    #[pyo3(transparent)]
    Str(String),
}

impl Felt252Input {
    fn into_felt252(self) -> Result<Felt252, PyErr> {
        match self {
            Felt252Input::Int(py_obj) => Python::with_gil(|py| {
                let hex_str = py_obj.call_method1(py, "__hex__", ())?.extract::<String>(py)?;
                Felt252::from_hex(&hex_str)
                    .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))
            }),
            Felt252Input::Str(s) => Felt252::from_hex(&s)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string())),
        }
    }
}

#[pyclass(name = "Relocatable")]
#[derive(Clone)]
pub struct PyRelocatable {
    pub(crate) inner: RustRelocatable,
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

    fn __sub__(&self, other: usize) -> PyResult<Self> {
        let result = (self.inner - other)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?;
        Ok(Self { inner: result })
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
