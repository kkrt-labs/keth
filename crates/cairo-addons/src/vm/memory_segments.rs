use cairo_vm::{
    types::relocatable::MaybeRelocatable, vm::vm_core::VirtualMachine as RustVirtualMachine,
};
use pyo3::prelude::*;

use crate::vm::{maybe_relocatable::PyMaybeRelocatable, relocatable::PyRelocatable};

use super::vm_consts::PyVmConst;

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

        vm.get_maybe(&key.inner).map(PyMaybeRelocatable::from).ok_or_else(|| {
            PyErr::new::<pyo3::exceptions::PyKeyError, _>(format!(
                "Memory address not found: {}",
                key.inner
            ))
        })
    }

    fn __setitem__(&self, key: PyRelocatable, value: PyMaybeRelocatable) -> PyResult<()> {
        let vm = unsafe { &mut *self.vm };

        if let Some(value) = vm.get_maybe(&key.inner) {
            return Err(PyErr::new::<pyo3::exceptions::PyKeyError, _>(format!(
                "Memory at key {} already has value: {}",
                key.inner, value
            )));
        }
        vm.insert_value(key.inner, value)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
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

    /// * `obj`: Expected to be a PyRelocatable or PyVmConst
    fn load_data(
        &mut self,
        obj: Py<PyAny>,
        data: Vec<PyMaybeRelocatable>,
        py: Python,
    ) -> PyResult<PyRelocatable> {
        // Try to extract PyRelocatable directly
        let ptr_addr = if let Ok(rel) = obj.extract::<PyRelocatable>(py) {
            rel.inner
        // Try through PyVmConst
        } else if let Ok(vm_const) = obj.extract::<PyVmConst>(py) {
            vm_const
                .get_address()
                .expect("Failed to get address from PyVmConst")
                .expect("No address for PyVmConst")
        } else {
            return Err(PyErr::new::<pyo3::exceptions::PyTypeError, _>(
                "Expected PyRelocatable or PyVmConst with valid address",
            ));
        };

        let data: Vec<MaybeRelocatable> = data.into_iter().map(|x| x.into()).collect();

        let result = unsafe {
            (*self.vm)
                .segments
                .load_data(ptr_addr, &data)
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
