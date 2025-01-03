use std::collections::HashMap;

use crate::vm::program::PyProgram;
use cairo_vm::{
    types::{
        layout_name::LayoutName,
        relocatable::{MaybeRelocatable, Relocatable},
    },
    vm::runners::{builtin_runner::BuiltinRunner, cairo_runner::CairoRunner as RustCairoRunner},
    Felt252,
};
use pyo3::prelude::*;

use crate::vm::{builtins::PyBuiltinList, relocatable::PyRelocatable};

use super::memory_segments::PyMemorySegmentManager;

use crate::vm::maybe_relocatable::PyMaybeRelocatable;

#[pyclass(name = "CairoRunner", unsendable)]
pub struct PyCairoRunner {
    inner: RustCairoRunner,
}

#[pymethods]
impl PyCairoRunner {
    #[new]
    #[pyo3(signature = (program, layout="plain", proof_mode=false))]
    fn new(program: &PyProgram, layout: &str, proof_mode: bool) -> PyResult<Self> {
        let layout = match layout {
            "plain" => LayoutName::plain,
            "small" => LayoutName::small,
            "dex" => LayoutName::dex,
            "recursive" => LayoutName::recursive,
            "starknet" => LayoutName::starknet,
            "starknet_with_keccak" => LayoutName::starknet_with_keccak,
            "recursive_large_output" => LayoutName::recursive_large_output,
            "recursive_with_poseidon" => LayoutName::recursive_with_poseidon,
            "all_cairo" => LayoutName::all_cairo,
            "all_solidity" => LayoutName::all_solidity,
            _ => return Err(PyErr::new::<pyo3::exceptions::PyValueError, _>("Invalid layout name")),
        };

        let inner = RustCairoRunner::new(
            &program.inner,
            layout,
            None, // dynamic_layout_params
            proof_mode,
            true, // trace_enabled
        )
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        Ok(Self { inner })
    }

    fn initialize_segments(&mut self) {
        self.inner.initialize_segments(None);
    }

    #[getter]
    fn program_base(&self) -> Option<PyRelocatable> {
        self.inner.program_base.map(|x| PyRelocatable { inner: x })
    }

    #[getter]
    fn execution_base(&self) -> Option<PyRelocatable> {
        // execution_base is not stored but we know it's created right after program_base
        // during initialize_segments(None), so we can derive it by incrementing the segment_index
        self.inner.program_base.map(|x| PyRelocatable {
            inner: Relocatable { segment_index: x.segment_index + 1, offset: 0 },
        })
    }

    #[pyo3(signature = (entrypoint, stack, return_fp))]
    fn initialize_function_entrypoint(
        &mut self,
        entrypoint: usize,
        stack: Vec<PyMaybeRelocatable>,
        return_fp: PyMaybeRelocatable,
    ) -> PyResult<PyRelocatable> {
        let stack: Vec<MaybeRelocatable> = stack.into_iter().map(|x| x.into()).collect();
        let return_fp: MaybeRelocatable = return_fp.into();
        let result = self
            .inner
            .initialize_function_entrypoint(entrypoint, stack, return_fp)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        Ok(PyRelocatable { inner: result })
    }

    #[pyo3(signature = (allow_missing_builtins))]
    fn initialize_builtins(&mut self, allow_missing_builtins: bool) -> PyResult<()> {
        self.inner
            .initialize_builtins(allow_missing_builtins)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))
    }

    #[getter]
    fn segments(&mut self) -> PyMemorySegmentManager {
        PyMemorySegmentManager { runner: &mut self.inner }
    }

    fn initialize_stack(&mut self, builtins: PyBuiltinList) -> Vec<PyMaybeRelocatable> {
        let builtins = builtins.into_builtin_names().unwrap();
        let mut stack = Vec::new();
        let builtin_runners =
            self.inner.vm.builtin_runners.iter().map(|b| (b.name(), b)).collect::<HashMap<_, _>>();
        for builtin_name in builtins {
            if let Some(builtin_runner) = builtin_runners.get(&builtin_name) {
                stack.append(&mut builtin_runner.initial_stack());
            } else {
                stack.push(Felt252::ZERO.into())
            }
        }
        stack.into_iter().map(PyMaybeRelocatable::from).collect()
    }

    fn initialize_zero_segment(&mut self) {
        for builtin_runner in self.inner.vm.builtin_runners.iter_mut() {
            if let BuiltinRunner::Mod(runner) = builtin_runner {
                runner.initialize_zero_segment(&mut self.inner.vm.segments);
            }
        }
    }

    fn initialize_vm(&mut self) -> PyResult<()> {
        match self.inner.initialize_vm() {
            Ok(_) => Ok(()),
            Err(e) => Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())),
        }
    }
}
