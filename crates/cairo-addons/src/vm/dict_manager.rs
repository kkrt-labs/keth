use cairo_vm::{
    hint_processor::builtin_hint_processor::dict_manager::{
        DictKey as RustDictKey, DictManager as RustDictManager, DictTracker,
    },
    types::relocatable::MaybeRelocatable,
};
use pyo3::{
    prelude::*,
    types::{IntoPyDict, PyDict, PyTuple},
    IntoPyObjectExt,
};
use std::{cell::RefCell, collections::HashMap, rc::Rc};

use super::{
    maybe_relocatable::PyMaybeRelocatable, relocatable::PyRelocatable, vm_consts::PyVmConst,
};

#[derive(FromPyObject, Eq, PartialEq, Hash, Debug)]
pub enum PyDictKey {
    #[pyo3(transparent)]
    Simple(PyMaybeRelocatable),
    #[pyo3(transparent)]
    Compound(Vec<PyMaybeRelocatable>),
}

impl<'py> IntoPyObject<'py> for PyDictKey {
    type Target = PyAny;
    type Output = Bound<'py, Self::Target>;
    type Error = std::convert::Infallible;

    fn into_pyobject(self, py: Python<'py>) -> Result<Self::Output, Self::Error> {
        let res = match self {
            PyDictKey::Simple(val) => val.into_bound_py_any(py),
            PyDictKey::Compound(vals) => {
                // Convert Vec to tuple
                let elements: Vec<Bound<'py, PyAny>> =
                    vals.into_iter().map(|v| v.into_bound_py_any(py).unwrap()).collect();
                let x = PyTuple::new(py, elements).map(|op| op.into_bound_py_any(py).unwrap());
                x
            }
        };

        Ok(res.unwrap())
    }
}

impl From<PyDictKey> for RustDictKey {
    fn from(value: PyDictKey) -> Self {
        match value {
            PyDictKey::Simple(val) => RustDictKey::Simple(val.into()),
            PyDictKey::Compound(vals) => {
                RustDictKey::Compound(vals.into_iter().map(|v| v.into()).collect())
            }
        }
    }
}

impl From<RustDictKey> for PyDictKey {
    fn from(value: RustDictKey) -> Self {
        match value {
            RustDictKey::Simple(val) => PyDictKey::Simple(val.into()),
            RustDictKey::Compound(vals) => {
                PyDictKey::Compound(vals.into_iter().map(|v| v.into()).collect())
            }
        }
    }
}

/// Object returned by DictManager.trackers enabling access to the trackers by index and mutating
/// the trackers with manager.trackers[index] = tracker
#[pyclass(name = "TrackerMapping", unsendable)]
pub struct PyTrackerMapping {
    inner: Rc<RefCell<RustDictManager>>,
}

#[pymethods]
impl PyTrackerMapping {
    fn __getitem__(&self, segment_index: isize) -> PyResult<PyDictTracker> {
        self.inner
            .borrow()
            .trackers
            .get(&segment_index)
            .cloned()
            .map(|tracker| PyDictTracker { inner: tracker })
            .ok_or_else(|| {
                PyErr::new::<pyo3::exceptions::PyKeyError, _>(format!(
                    "segment_index {} not found",
                    segment_index
                ))
            })
    }

    fn __setitem__(&mut self, segment_index: isize, value: PyDictTracker) -> PyResult<()> {
        self.inner.borrow_mut().trackers.insert(segment_index, value.inner);
        Ok(())
    }
}

// Object returned by DictManager.preimages enabling access to the preimages by index and mutating
/// the preimages with manager.preimages[index] = preimage
#[pyclass(name = "PreimagesMapping", unsendable)]
pub struct PyPreimagesMapping {
    inner: Rc<RefCell<RustDictManager>>,
}

#[pymethods]
impl PyPreimagesMapping {
    fn __getitem__(&self, key: PyMaybeRelocatable) -> PyResult<PyDictKey> {
        Ok(self
            .inner
            .borrow()
            .preimages
            .get(&key.clone().into())
            .cloned()
            .ok_or_else(|| {
                PyErr::new::<pyo3::exceptions::PyKeyError, _>(format!("key {:?} not found", key))
            })?
            .into())
    }

    fn __setitem__(&mut self, key: PyMaybeRelocatable, value: PyDictKey) -> PyResult<()> {
        self.inner.borrow_mut().preimages.insert(key.into(), value.into());
        Ok(())
    }

    fn update(&mut self, other: Bound<'_, PyDict>) -> PyResult<()> {
        let other_dict = other.extract::<HashMap<PyMaybeRelocatable, PyDictKey>>()?;
        self.inner
            .borrow_mut()
            .preimages
            .extend(other_dict.into_iter().map(|(k, v)| (k.into(), v.into())));
        Ok(())
    }

    fn __repr__(&self) -> PyResult<String> {
        let inner = self.inner.borrow();
        let mut pairs: Vec<_> = inner.preimages.iter().collect();
        pairs.sort_by(|(k1, _), (k2, _)| k1.partial_cmp(k2).unwrap_or(std::cmp::Ordering::Equal));
        let data_str =
            pairs.into_iter().map(|(k, v)| format!("{}: {}", k, v)).collect::<Vec<_>>().join(", ");
        Ok(format!("PreimagesMapping({{{}}})", data_str))
    }
}
#[pyclass(name = "DictManager", unsendable)]
pub struct PyDictManager {
    pub inner: Rc<RefCell<RustDictManager>>,
}

#[pymethods]
impl PyDictManager {
    #[new]
    fn new() -> Self {
        Self { inner: Rc::new(RefCell::new(RustDictManager::new())) }
    }

    #[getter]
    fn trackers(&self) -> PyResult<PyTrackerMapping> {
        Ok(PyTrackerMapping { inner: self.inner.clone() })
    }

    #[getter]
    fn get_preimages(&self) -> PyResult<PyPreimagesMapping> {
        Ok(PyPreimagesMapping { inner: self.inner.clone() })
    }

    #[setter]
    fn set_preimages(&mut self, value: Bound<'_, PyDict>) -> PyResult<()> {
        let preimages = value.extract::<HashMap<PyMaybeRelocatable, PyDictKey>>()?;
        self.inner.borrow_mut().preimages =
            preimages.into_iter().map(|(k, v)| (k.into(), v.into())).collect();
        Ok(())
    }

    fn get_tracker(&self, obj: Py<PyAny>, py: Python) -> PyResult<PyDictTracker> {
        // Extract segment_index from either PyRelocatable or PyVmConst
        let segment_index = if let Ok(rel) = obj.extract::<PyRelocatable>(py) {
            rel.inner.segment_index
        } else if let Ok(vm_const) = obj.extract::<PyVmConst>(py) {
            if let Ok(Some(addr)) = vm_const.get_address() {
                addr.segment_index
            } else {
                return Err(PyErr::new::<pyo3::exceptions::PyTypeError, _>(
                    "PyVmConst doesn't have a valid address",
                ));
            }
        } else {
            return Err(PyErr::new::<pyo3::exceptions::PyTypeError, _>(
                "Expected PyRelocatable or PyVmConst with valid address",
            ));
        };

        // Use segment_index to get the tracker
        self.inner
            .borrow()
            .trackers
            .get(&segment_index)
            .cloned()
            .map(|tracker| PyDictTracker { inner: tracker })
            .ok_or_else(|| {
                PyErr::new::<pyo3::exceptions::PyKeyError, _>(format!(
                    "segment_index {} not found",
                    segment_index
                ))
            })
    }

    fn get_dict(&self, dict_ptr: Py<PyAny>, py: Python) -> PyResult<Py<PyDict>> {
        let tracker = self.get_tracker(dict_ptr, py)?;
        let dict = tracker.data();
        Ok(dict.into_py_dict(py).unwrap().unbind())
    }

    fn insert(&mut self, segment_index: isize, value: &PyDictTracker) -> PyResult<()> {
        if self.inner.borrow().trackers.contains_key(&segment_index) {
            return Err(PyErr::new::<pyo3::exceptions::PyValueError, _>(
                "Segment index already exists",
            ));
        };
        self.inner.borrow_mut().trackers.insert(segment_index, value.inner.clone());
        Ok(())
    }

    fn get_value(&self, segment_index: isize, key: PyDictKey) -> PyResult<PyMaybeRelocatable> {
        let value = self
            .inner
            .borrow_mut()
            .trackers
            .get_mut(&segment_index)
            .ok_or_else(|| {
                PyErr::new::<pyo3::exceptions::PyValueError, _>("Segment index not found")
            })?
            .get_value(&key.into())
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyValueError, _>(e.to_string()))?
            .clone();
        Ok(value.into())
    }

    fn get_default_value(&self, segment_index: isize) -> PyResult<PyMaybeRelocatable> {
        let dict_manager = self.inner.borrow();
        let tracker = dict_manager.trackers.get(&segment_index).unwrap();
        let default_value = tracker.get_default_value().cloned().ok_or_else(|| {
            PyErr::new::<pyo3::exceptions::PyValueError, _>(format!(
                "Default value not found for segment index {}",
                segment_index
            ))
        })?;
        Ok(default_value.into())
    }
}

#[pyclass(name = "DictTracker")]
#[derive(Clone, Debug)]
pub struct PyDictTracker {
    inner: DictTracker,
}

#[pymethods]
impl PyDictTracker {
    #[new]
    #[pyo3(signature = (data, current_ptr, default_value=None))]
    fn new(
        data: HashMap<PyDictKey, PyMaybeRelocatable>,
        current_ptr: PyRelocatable,
        default_value: Option<PyMaybeRelocatable>,
    ) -> PyResult<Self> {
        let data: HashMap<RustDictKey, MaybeRelocatable> =
            data.into_iter().map(|(k, v)| (k.into(), v.into())).collect();

        if let Some(default_value) = default_value {
            let default_value = default_value.into();
            Ok(Self {
                inner: DictTracker::new_default_dict(current_ptr.inner, &default_value, Some(data)),
            })
        } else {
            Ok(Self { inner: DictTracker::new_with_initial(current_ptr.inner, data) })
        }
    }

    #[getter]
    fn current_ptr(&self) -> PyRelocatable {
        PyRelocatable { inner: self.inner.current_ptr }
    }

    #[setter]
    fn set_current_ptr(&mut self, value: PyRelocatable) {
        self.inner.current_ptr = value.inner;
    }

    #[getter]
    fn data(&self) -> HashMap<PyDictKey, PyMaybeRelocatable> {
        self.inner
            .get_dictionary_ref()
            .iter()
            .map(|(k, v)| (PyDictKey::from(k.clone()), PyMaybeRelocatable::from(v.clone())))
            .collect()
    }

    fn __repr__(&self) -> PyResult<String> {
        let mut pairs: Vec<_> = self.inner.get_dictionary_ref().iter().collect();

        // Sort by key
        pairs.sort_by(|(k1, _), (k2, _)| k1.partial_cmp(k2).unwrap_or(std::cmp::Ordering::Equal));

        let data_str =
            pairs.into_iter().map(|(k, v)| format!("{}: {}", k, v)).collect::<Vec<_>>().join(", ");

        Ok(format!(
            "DictTracker(data={{{}}}, current_ptr=Relocatable(segment_index={}, offset={}))",
            data_str, self.inner.current_ptr.segment_index, self.inner.current_ptr.offset
        ))
    }

    // Note: no setters are implemented for these because they would require the inner tracker to be
    // a mutable borrow, which is not implemented yet and would require more refactoring.

    #[getter]
    fn name(&self) -> String {
        self.inner.name.clone().unwrap_or_default()
    }

    #[getter]
    fn is_squashed(&self) -> bool {
        self.inner.is_squashed
    }
}
