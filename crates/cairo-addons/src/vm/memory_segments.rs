use cairo_vm::{
    types::relocatable::MaybeRelocatable,
    vm::vm_memory::memory_segments::MemorySegmentManager as RustMemorySegmentManager,
};
use pyo3::prelude::*;

use crate::vm::{maybe_relocatable::PyMaybeRelocatable, relocatable::PyRelocatable};

#[pyclass(name = "MemorySegmentManager", unsendable)]
pub struct PyMemorySegmentManager {
    pub(crate) inner: RustMemorySegmentManager,
}

#[pymethods]
impl PyMemorySegmentManager {
    #[new]
    fn new() -> Self {
        Self { inner: RustMemorySegmentManager::new() }
    }

    fn add(&mut self) -> PyRelocatable {
        self.inner.add().into()
    }

    fn add_temporary_segment(&mut self) -> PyRelocatable {
        self.inner.add_temporary_segment().into()
    }

    fn load_data(
        &mut self,
        ptr: &PyRelocatable,
        data: Vec<PyMaybeRelocatable>,
    ) -> PyResult<PyRelocatable> {
        let data: Vec<MaybeRelocatable> = data.into_iter().map(|x| x.into()).collect();

        let result = self
            .inner
            .load_data(ptr.inner, &data)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        Ok(result.into())
    }

    fn compute_effective_sizes(&mut self) {
        self.inner.compute_effective_sizes();
    }

    fn get_segment_used_size(&self, segment_index: usize) -> Option<usize> {
        self.inner.get_segment_used_size(segment_index)
    }

    fn get_segment_size(&self, segment_index: usize) -> Option<usize> {
        self.inner.get_segment_size(segment_index)
    }
}
