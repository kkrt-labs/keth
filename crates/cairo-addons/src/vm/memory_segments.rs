use cairo_vm::{
    types::relocatable::MaybeRelocatable, vm::vm_core::VirtualMachine as RustVirtualMachine,
};
use pyo3::prelude::*;

use crate::vm::{maybe_relocatable::PyMaybeRelocatable, relocatable::PyRelocatable};

#[pyclass(name = "MemorySegmentManager", unsendable)]
pub struct PyMemorySegmentManager {
    pub(crate) vm: *mut RustVirtualMachine,
}

#[derive(FromPyObject)]
enum GenArgInput {
    Single(PyMaybeRelocatable),
    Multiple(Vec<PyMaybeRelocatable>),
}

/// Enables syntax `segments.memory.<op>`
#[pyclass(name = "MemoryWrapper", unsendable)]
pub struct PyMemoryWrapper {
    pub(crate) vm: *mut RustVirtualMachine,
}

#[pymethods]
impl PyMemoryWrapper {
    fn get(&self, key: PyRelocatable) -> Option<PyMaybeRelocatable> {
        unsafe { (*self.vm).get_maybe(&key.inner).map(PyMaybeRelocatable::from) }
    }

    fn __getitem__(&self, key: PyRelocatable) -> PyResult<PyMaybeRelocatable> {
        let vm = unsafe { &mut *self.vm };

        match vm.get_maybe(&key.inner) {
            Some(value) => {
                let py_value = PyMaybeRelocatable::from(value);
                Ok(py_value)
            }
            None => Err(PyErr::new::<pyo3::exceptions::PyKeyError, _>(format!(
                "Memory address not found: {}",
                key.inner
            ))),
        }
    }
}

#[pymethods]
impl PyMemorySegmentManager {
    #[getter]
    fn memory(&self) -> PyMemoryWrapper {
        PyMemoryWrapper { vm: self.vm }
    }

    fn add(&mut self) -> PyRelocatable {
        unsafe { (*self.vm).segments.add().into() }
    }

    fn add_temporary_segment(&mut self) -> PyRelocatable {
        unsafe { (*self.vm).segments.add_temporary_segment().into() }
    }

    fn load_data(
        &mut self,
        ptr: &PyRelocatable,
        data: Vec<PyMaybeRelocatable>,
    ) -> PyResult<PyRelocatable> {
        let data: Vec<MaybeRelocatable> = data.into_iter().map(|x| x.into()).collect();

        let result = unsafe {
            (*self.vm)
                .segments
                .load_data(ptr.inner, &data)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?
        };

        Ok(result.into())
    }

    fn get_segment_used_size(&self, segment_index: usize) -> Option<usize> {
        unsafe { (*self.vm).segments.get_segment_used_size(segment_index) }
    }

    fn get_segment_size(&self, segment_index: usize) -> Option<usize> {
        unsafe { (*self.vm).segments.get_segment_size(segment_index) }
    }

    fn compute_effective_sizes(&mut self) -> Vec<usize> {
        unsafe { (*self.vm).segments.compute_effective_sizes().clone() }
    }

    fn gen_arg(&self, arg: GenArgInput) -> PyResult<PyMaybeRelocatable> {
        let result = match arg {
            GenArgInput::Single(arg) => {
                let arg: MaybeRelocatable = arg.into();
                let result: Result<
                    MaybeRelocatable,
                    cairo_vm::vm::errors::memory_errors::MemoryError,
                > = unsafe { (*self.vm).segments.gen_arg(&arg) };
                result
            }
            GenArgInput::Multiple(arg) => {
                let arg: Vec<MaybeRelocatable> = arg.into_iter().map(|x| x.into()).collect();
                let result: Result<
                    MaybeRelocatable,
                    cairo_vm::vm::errors::memory_errors::MemoryError,
                > = unsafe { (*self.vm).segments.gen_arg(&arg) };
                result
            }
        };
        match result {
            Ok(value) => Ok(value.into()),
            Err(e) => Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())),
        }
    }
}
