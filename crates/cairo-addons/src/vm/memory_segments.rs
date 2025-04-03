use cairo_vm::{
    types::relocatable::{MaybeRelocatable, Relocatable},
    vm::vm_memory::{memory::Memory, memory_segments::MemorySegmentManager},
};
use pyo3::prelude::*;

use crate::vm::{maybe_relocatable::PyMaybeRelocatable, relocatable::PyRelocatable};

use super::vm_consts::PyVmConst;

#[pyclass(name = "MemorySegmentManager", unsendable)]
pub struct PyMemorySegmentManager {
    pub(crate) inner: *mut MemorySegmentManager,
}

#[derive(FromPyObject)]
enum GenArgInput {
    Single(PyMaybeRelocatable),
    Multiple(Vec<PyMaybeRelocatable>),
}

/// Enables syntax `segments.memory.<op>`
#[pyclass(name = "MemoryWrapper", unsendable)]
pub struct PyMemoryWrapper {
    pub(crate) inner: *mut Memory,
}

//TODO: remove after https://github.com/lambdaclass/cairo-vm/pull/2039
fn memory_get(memory: &mut Memory, key: Relocatable) -> Option<MaybeRelocatable> {
    match memory.get_relocatable(key) {
        Ok(relocatable) => Some(relocatable.into()),
        Err(_) => {
            let value = memory.get_integer(key).map(|x| x.into_owned()).ok()?;
            Some(value.into())
        }
    }
}

#[pymethods]
impl PyMemoryWrapper {
    fn get(&self, key: PyRelocatable) -> Option<PyMaybeRelocatable> {
        let memory = unsafe { &mut *self.inner };
        Some(memory_get(memory, key.inner)?.into())
    }

    fn __getitem__(&self, key: PyRelocatable) -> PyResult<PyMaybeRelocatable> {
        let memory = unsafe { &mut *self.inner };

        memory_get(memory, key.inner).map(PyMaybeRelocatable::from).ok_or_else(|| {
            PyErr::new::<pyo3::exceptions::PyKeyError, _>(format!(
                "Memory address not found: {}",
                key.inner
            ))
        })
    }

    fn __setitem__(&self, key: PyRelocatable, value: PyMaybeRelocatable) -> PyResult<()> {
        let memory = unsafe { &mut *self.inner };

        if let Some(value) = memory_get(memory, key.inner) {
            return Err(PyErr::new::<pyo3::exceptions::PyKeyError, _>(format!(
                "Memory at key {} already has value: {}",
                key.inner, value
            )));
        }
        memory
            .insert_value(key.inner, value)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }
}

#[pymethods]
impl PyMemorySegmentManager {
    #[getter]
    pub fn memory(&self) -> PyMemoryWrapper {
        let memory = unsafe { &mut (*self.inner).memory };
        PyMemoryWrapper { inner: memory }
    }

    fn add(&mut self) -> PyRelocatable {
        unsafe { (*self.inner).add().into() }
    }

    fn add_temporary_segment(&mut self) -> PyRelocatable {
        unsafe { (*self.inner).add_temporary_segment().into() }
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
            (*self.inner)
                .load_data(ptr_addr, &data)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?
        };

        Ok(result.into())
    }

    fn get_segment_used_size(&self, segment_index: usize) -> Option<usize> {
        unsafe { (*self.inner).get_segment_used_size(segment_index) }
    }

    fn get_segment_size(&self, segment_index: usize) -> Option<usize> {
        unsafe { (*self.inner).get_segment_size(segment_index) }
    }

    fn compute_effective_sizes(&mut self) -> Vec<usize> {
        unsafe { (*self.inner).compute_effective_sizes().clone() }
    }

    fn gen_arg(&self, arg: GenArgInput) -> PyResult<PyMaybeRelocatable> {
        let result = match arg {
            GenArgInput::Single(arg) => {
                let arg: MaybeRelocatable = arg.into();
                let result: Result<
                    MaybeRelocatable,
                    cairo_vm::vm::errors::memory_errors::MemoryError,
                > = unsafe { (*self.inner).gen_arg(&arg) };
                result
            }
            GenArgInput::Multiple(arg) => {
                let arg: Vec<MaybeRelocatable> = arg.into_iter().map(|x| x.into()).collect();
                let result: Result<
                    MaybeRelocatable,
                    cairo_vm::vm::errors::memory_errors::MemoryError,
                > = unsafe { (*self.inner).gen_arg(&arg) };
                result
            }
        };
        match result {
            Ok(value) => Ok(value.into()),
            Err(e) => Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())),
        }
    }
}
