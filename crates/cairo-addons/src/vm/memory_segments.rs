use cairo_vm::{
    types::relocatable::MaybeRelocatable, vm::runners::cairo_runner::CairoRunner as RustCairoRunner,
};
use pyo3::prelude::*;

use crate::vm::{maybe_relocatable::PyMaybeRelocatable, relocatable::PyRelocatable};

#[pyclass(name = "MemorySegmentManager", unsendable)]
pub struct PyMemorySegmentManager {
    pub(crate) runner: *mut RustCairoRunner,
}

/// Enables syntax `segments.memory.<op>`
#[pyclass(name = "MemoryWrapper", unsendable)]
pub struct PyMemoryWrapper {
    pub(crate) runner: *mut RustCairoRunner,
}

#[pymethods]
impl PyMemoryWrapper {
    fn get(&self, key: PyRelocatable) -> Option<PyMaybeRelocatable> {
        unsafe { (*self.runner).vm.get_maybe(&key.inner).map(PyMaybeRelocatable::from) }
    }
}

#[pymethods]
impl PyMemorySegmentManager {
    #[getter]
    fn memory(&self) -> PyMemoryWrapper {
        PyMemoryWrapper { runner: self.runner }
    }

    fn add(&mut self) -> PyRelocatable {
        unsafe { (*self.runner).vm.segments.add().into() }
    }

    fn add_temporary_segment(&mut self) -> PyRelocatable {
        unsafe { (*self.runner).vm.segments.add_temporary_segment().into() }
    }

    fn load_data(
        &mut self,
        ptr: &PyRelocatable,
        data: Vec<PyMaybeRelocatable>,
    ) -> PyResult<PyRelocatable> {
        let data: Vec<MaybeRelocatable> = data.into_iter().map(|x| x.into()).collect();

        let result = unsafe {
            (*self.runner)
                .vm
                .segments
                .load_data(ptr.inner, &data)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?
        };

        Ok(result.into())
    }

    fn get_segment_used_size(&self, segment_index: usize) -> Option<usize> {
        unsafe { (*self.runner).vm.segments.get_segment_used_size(segment_index) }
    }

    fn get_segment_size(&self, segment_index: usize) -> Option<usize> {
        unsafe { (*self.runner).vm.segments.get_segment_size(segment_index) }
    }

    fn compute_effective_sizes(&mut self) -> Vec<usize> {
        unsafe { (*self.runner).vm.segments.compute_effective_sizes().clone() }
    }
}
