use cairo_vm::Felt252;
use pyo3::{prelude::*, FromPyObject};

#[derive(FromPyObject)]
pub struct Felt252Input(PyObject);

impl Felt252Input {
    pub(crate) fn into_felt252(self) -> Result<Felt252, PyErr> {
        Python::with_gil(|py| {
            let hex_str = self.0.call_method1(py, "__format__", ("x",))?.extract::<String>(py)?;
            let hex_str = format!("0x{}", hex_str);
            Felt252::from_hex(&hex_str)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))
        })
    }
}

#[pyclass(name = "Felt")]
#[derive(Clone, Eq, PartialEq, Hash)]
pub struct PyFelt {
    pub(crate) inner: Felt252,
}

#[pymethods]
impl PyFelt {
    #[new]
    fn new(value: Felt252Input) -> PyResult<Self> {
        let inner = value.into_felt252()?;
        Ok(Self { inner })
    }

    fn __str__(&self) -> String {
        self.inner.to_string()
    }

    fn __repr__(&self) -> String {
        format!("Felt('{}')", self.inner)
    }

    fn __eq__(&self, other: &PyFelt) -> bool {
        self.inner == other.inner
    }

    fn __hash__(&self) -> PyResult<isize> {
        Ok(self.inner.to_bytes_be().iter().fold(0isize, |acc, &x| acc ^ (x as isize)))
    }

    fn __add__(&self, other: &PyFelt) -> Self {
        Self { inner: self.inner + other.inner }
    }

    fn __sub__(&self, other: &PyFelt) -> Self {
        Self { inner: self.inner - other.inner }
    }

    fn __mul__(&self, other: &PyFelt) -> Self {
        Self { inner: self.inner * other.inner }
    }

    fn __neg__(&self) -> Self {
        Self { inner: -self.inner }
    }

    fn pow(&self, exp: u32) -> Self {
        Self { inner: self.inner.pow(exp) }
    }

    fn sqrt(&self) -> Option<Self> {
        self.inner.sqrt().map(|x| Self { inner: x })
    }

    fn is_zero(&self) -> bool {
        self.inner == Felt252::ZERO
    }

    fn __int__(&self, py: Python<'_>) -> PyObject {
        self.inner.to_bigint().into_py(py)
    }
}

impl From<Felt252> for PyFelt {
    fn from(felt: Felt252) -> Self {
        Self { inner: felt }
    }
}
