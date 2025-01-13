use cairo_vm::{
    hint_processor::builtin_hint_processor::dict_manager::{
        DictKey as RustDictKey, DictManager as RustDictManager, DictTracker,
    },
    types::relocatable::MaybeRelocatable,
};
use pyo3::{prelude::*, types::PyTuple};
use std::{cell::RefCell, collections::HashMap, rc::Rc};

use super::{maybe_relocatable::PyMaybeRelocatable, relocatable::PyRelocatable};

#[derive(FromPyObject, Eq, PartialEq, Hash)]
pub enum PyDictKey {
    #[pyo3(transparent)]
    Simple(PyMaybeRelocatable),
    #[pyo3(transparent)]
    Compound(Vec<PyMaybeRelocatable>),
}

impl IntoPy<PyObject> for PyDictKey {
    fn into_py(self, py: Python<'_>) -> PyObject {
        match self {
            PyDictKey::Simple(val) => val.into_py(py),
            PyDictKey::Compound(vals) => {
                // Convert Vec to tuple
                let elements: Vec<PyObject> = vals.into_iter().map(|v| v.into_py(py)).collect();
                PyTuple::new_bound(py, elements).into()
            }
        }
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
    fn __getitem__(&self, key: isize) -> PyResult<PyDictTracker> {
        self.inner
            .borrow()
            .trackers
            .get(&key)
            .cloned()
            .map(|tracker| PyDictTracker { inner: tracker })
            .ok_or_else(|| {
                PyErr::new::<pyo3::exceptions::PyKeyError, _>(format!("Key {} not found", key))
            })
    }

    fn __setitem__(&mut self, key: isize, value: PyDictTracker) -> PyResult<()> {
        self.inner.borrow_mut().trackers.insert(key, value.inner);
        Ok(())
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
}

#[pyclass(name = "DictTracker")]
#[derive(Clone)]
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
}
