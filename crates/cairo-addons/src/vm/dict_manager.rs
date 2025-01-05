use cairo_vm::{
    hint_processor::builtin_hint_processor::dict_manager::{
        DictManager as RustDictManager, DictTracker,
    },
    types::relocatable::MaybeRelocatable,
};
use pyo3::prelude::*;
use std::{cell::RefCell, collections::HashMap, rc::Rc};

use super::{maybe_relocatable::PyMaybeRelocatable, relocatable::PyRelocatable};

#[pyclass(name = "DictManager", unsendable)]
pub struct PyDictManager {
    pub inner: Rc<RefCell<RustDictManager>>,
}

#[pymethods]
impl PyDictManager {
    fn insert(&mut self, segment_index: isize, value: &PyDictTracker) -> PyResult<()> {
        if self.inner.borrow().trackers.contains_key(&segment_index) {
            return Err(PyErr::new::<pyo3::exceptions::PyValueError, _>(
                "Segment index already exists",
            ));
        };
        self.inner.borrow_mut().trackers.insert(segment_index, value.inner.clone());
        Ok(())
    }

    fn get_value(
        &self,
        segment_index: isize,
        key: PyMaybeRelocatable,
    ) -> PyResult<PyMaybeRelocatable> {
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
pub struct PyDictTracker {
    inner: DictTracker,
}

#[pymethods]
impl PyDictTracker {
    // Note: This is a temporary implementation, need to understand why HashMap<PyMaybeRelocatable,
    // PyMaybeRelocatable> is not working
    #[new]
    fn new(
        keys: Vec<PyMaybeRelocatable>,
        values: Vec<PyMaybeRelocatable>,
        current_ptr: PyRelocatable,
    ) -> PyResult<Self> {
        let data: HashMap<MaybeRelocatable, MaybeRelocatable> =
            keys.into_iter().zip(values).map(|(k, v)| (k.into(), v.into())).collect();

        Ok(Self { inner: DictTracker::new_with_initial(current_ptr.inner, data) })
    }
}
