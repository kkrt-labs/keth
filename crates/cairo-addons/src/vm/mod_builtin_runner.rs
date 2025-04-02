//! Python bindings for Cairo VM's `ModBuiltinRunner`.
//!
//! This module bridges Rust and Python via PyO3, managing complex lifetime and ownership
//! scenarios. Notably, we use `Bound<'py, T>` to tie Python references to the GIL,
//! extracting them early to ensure validity across calls - ensuring we can use a reference to the
//! `ModBuiltinRunner` object throughout the lifetime of the `fill_memory` call.

use cairo_vm::vm::runners::builtin_runner::ModBuiltinRunner;
use pyo3::{
    exceptions::{PyTypeError, PyValueError},
    pyclass, pymethods,
    types::{PyAny, PyAnyMethods, PyTuple},
    Bound, FromPyObject, PyResult, Python,
};

use super::{memory_segments::PyMemoryWrapper, relocatable::PyRelocatable};

/// Argument for `ModBuiltinRunner::fill_memory` function.
///
/// Holds GIL-bound references for safe lifetime management in Python-Rust interop.
/// Fields are extracted from Python tuples and tied to the GIL via `Bound<'py, T>`.
#[derive(Debug)]
struct PyFillMemoryArgs<'py> {
    rel: Bound<'py, PyRelocatable>,
    runner: Bound<'py, PyModBuiltinRunner>,
    size: usize,
}

/// Extracts the individual objects from of `PyFillMemoryArgs` into a tuple.
impl<'py> FromPyObject<'py> for PyFillMemoryArgs<'py> {
    fn extract_bound(ob: &Bound<'py, PyAny>) -> PyResult<Self> {
        // Ensure the input Python object is a tuple
        let tuple = ob
            .downcast::<PyTuple>()
            .map_err(|_| PyTypeError::new_err("Argument must be a 3-tuple or None"))?;

        // Should receive a tuple of length 3
        let len = tuple.len()?;
        if len != 3 {
            return Err(PyValueError::new_err(format!("Expected a tuple of length 3, got {}", len)));
        }

        // Extract elements from the tuple:
        // - Use downcast to get Bound references for pyclass types, so as to ensure they remain
        //   valid for the duration of the `fill_memory` call.
        // - Use extract for standard types like usize
        let binding_rel = tuple.get_item(0)?;
        let rel_bound = binding_rel.downcast::<PyRelocatable>().map_err(|e| {
            PyTypeError::new_err(format!("Tuple element 0 is not PyRelocatable: {}", e))
        })?;

        let binding_runner = tuple.get_item(1)?;
        let runner_bound = binding_runner.downcast::<PyModBuiltinRunner>().map_err(|e| {
            PyTypeError::new_err(format!("Tuple element 1 is not PyModBuiltinRunner: {}", e))
        })?;

        let size = tuple
            .get_item(2)?
            .extract::<usize>()
            .map_err(|e| PyTypeError::new_err(format!("Tuple element 2 is not usize: {}", e)))?;
        Ok(PyFillMemoryArgs { rel: rel_bound.to_owned(), runner: runner_bound.to_owned(), size })
    }
}

/// Python wrapper for `ModBuiltinRunner`.
///
/// Ensures thread-safety (`unsendable`) and immutability (`frozen`) in Python.
#[pyclass(name = "ModBuiltinRunner", unsendable, frozen)]
#[derive(Debug, Clone)]
pub struct PyModBuiltinRunner {
    pub inner: ModBuiltinRunner,
}

#[pymethods]
impl PyModBuiltinRunner {
    /// Fills memory with modular operations.
    ///
    /// # Arguments
    /// - `memory`: Mutable memory wrapper.
    /// - `add_mod`: Optional `(PyRelocatable, PyModBuiltinRunner, size)` tuple for addition.
    /// - `mul_mod`: Optional `(PyRelocatable, PyModBuiltinRunner, size)` tuple for multiplication.
    ///
    /// # Notes
    /// - Extracts references outside closures to extend lifetimes.
    /// - Direct `fill_memory` call is a compatibility workaround - the recommended way is to use
    /// the `vm` object instead.
    #[pyo3(signature = (memory, add_mod=None, mul_mod=None))]
    #[staticmethod]
    fn fill_memory<'py>(
        _py: Python<'py>,
        memory: &PyMemoryWrapper,
        add_mod: Option<PyFillMemoryArgs<'py>>,
        mul_mod: Option<PyFillMemoryArgs<'py>>,
    ) -> PyResult<()> {
        let memory_inner = unsafe { &mut *memory.inner }; // Assuming memory.inner is *mut Memory

        // Extract references with proper lifetime management.
        let add_mod_runner_ref = add_mod
            .as_ref()
            .map(|args| (args.rel.get().inner, &args.runner.get().inner, args.size));
        let mul_mod_runner_ref = mul_mod
            .as_ref()
            .map(|args| (args.rel.get().inner, &args.runner.get().inner, args.size));

        // Note: It is not recommended to call fill_memory on the ModBuiltinRunner, directly, but
        // because we're working in compatibility mode with python, we don't have access to
        // the `vm` object here.
        ModBuiltinRunner::fill_memory(memory_inner, add_mod_runner_ref, mul_mod_runner_ref)
            .map_err(|e| PyValueError::new_err(format!("Error filling memory: {}", e)))?;

        Ok(())
    }

    #[getter]
    fn instance_def(&self) -> PyModBuiltinInstanceDef {
        PyModBuiltinInstanceDef { ratio: self.inner.ratio(), batch_size: self.inner.batch_size() }
    }
}
// A wrapper around the fields of the ModInstanceDef struct, which is private in the
// ModBuiltinRunner struct. We need to expose these fields from `mod_builtin_runner.instance_def` to
// the Python bindings. Note: word_bit_len is not included in the wrapper, because it is not
// accessible (nor required, for now.)
#[pyclass(name = "ModBuiltinInstanceDef", unsendable, frozen)]
#[derive(Debug, Clone)]
pub struct PyModBuiltinInstanceDef {
    ratio: Option<u32>,
    batch_size: usize,
}

#[pymethods]
impl PyModBuiltinInstanceDef {
    #[getter]
    fn ratio(&self) -> Option<u32> {
        self.ratio
    }

    #[getter]
    fn batch_size(&self) -> usize {
        self.batch_size
    }
}
