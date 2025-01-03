use std::collections::HashMap;

use crate::vm::program::PyProgram;
use cairo_vm::{
    hint_processor::builtin_hint_processor::builtin_hint_processor_definition::BuiltinHintProcessor,
    types::{
        builtin_name::BuiltinName,
        layout_name::LayoutName,
        relocatable::{MaybeRelocatable, Relocatable},
    },
    vm::{
        runners::{builtin_runner::BuiltinRunner, cairo_runner::CairoRunner as RustCairoRunner},
        security::verify_secure_runner,
    },
    Felt252,
};
use pyo3::prelude::*;

use crate::vm::{
    builtins::PyBuiltinList, maybe_relocatable::PyMaybeRelocatable, relocatable::PyRelocatable,
    relocated_trace::PyRelocatedTraceEntry, run_resources::PyRunResources,
};
use num_traits::Zero;

use super::memory_segments::PyMemorySegmentManager;

#[pyclass(name = "CairoRunner", unsendable)]
pub struct PyCairoRunner {
    inner: RustCairoRunner,
    allow_missing_builtins: bool,
    builtins: Vec<BuiltinName>,
}

#[pymethods]
impl PyCairoRunner {
    #[new]
    #[pyo3(signature = (program, layout="plain", proof_mode=false, allow_missing_builtins=false))]
    fn new(
        program: &PyProgram,
        layout: &str,
        proof_mode: bool,
        allow_missing_builtins: bool,
    ) -> PyResult<Self> {
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

        Ok(Self { inner, allow_missing_builtins, builtins: vec![] })
    }

    /// Initialize the runner with the given builtins and stack.
    ///
    /// Mainly CairoRunner::initialize but with the ability to pass a stack and builtins.
    pub fn initialize(
        &mut self,
        builtins: PyBuiltinList,
        stack: Vec<PyMaybeRelocatable>,
        entrypoint: usize,
    ) -> PyResult<PyRelocatable> {
        self.inner
            .initialize_builtins(self.allow_missing_builtins)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        self.inner.initialize_segments(None);
        let initial_stack = self.builtins_stack(builtins);
        let stack = initial_stack.into_iter().chain(stack.into_iter().map(|x| x.into())).collect();

        let return_fp = self.inner.vm.add_memory_segment();
        let end = self
            .inner
            .initialize_function_entrypoint(entrypoint, stack, return_fp.into())
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        for builtin_runner in self.inner.vm.builtin_runners.iter_mut() {
            if let BuiltinRunner::Mod(runner) = builtin_runner {
                runner.initialize_zero_segment(&mut self.inner.vm.segments);
            }
        }
        self.inner
            .initialize_vm()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(PyRelocatable { inner: end })
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

    #[getter]
    fn ap(&self) -> PyRelocatable {
        PyRelocatable { inner: self.inner.vm.get_ap() }
    }

    #[getter]
    fn segments(&mut self) -> PyMemorySegmentManager {
        PyMemorySegmentManager { runner: &mut self.inner }
    }

    fn run_until_pc(&mut self, address: PyRelocatable, resources: PyRunResources) -> PyResult<()> {
        let mut hint_processor = BuiltinHintProcessor::new(HashMap::new(), resources.inner);
        self.inner
            .run_until_pc(address.inner, &mut hint_processor)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        self.inner
            .end_run(false, false, &mut hint_processor)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }

    fn verify_and_relocate(&mut self, offset: usize) -> PyResult<()> {
        self.inner
            .vm
            .verify_auto_deductions()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        self.read_return_values(offset)?;

        verify_secure_runner(&self.inner, true, None)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        self.inner
            .relocate(true)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        Ok(())
    }

    #[getter]
    fn relocated_trace(&self) -> PyResult<Vec<PyRelocatedTraceEntry>> {
        Ok(self
            .inner
            .relocated_trace
            .clone()
            .unwrap_or_default()
            .into_iter()
            .map(PyRelocatedTraceEntry::from)
            .collect())
    }
}

impl PyCairoRunner {
    fn builtins_stack(&mut self, builtins: PyBuiltinList) -> Vec<MaybeRelocatable> {
        let builtins = builtins.into_builtin_names().unwrap();
        self.builtins = builtins.clone();
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
        stack
    }

    /// Mainly like `CairoRunner::read_return_values` but with an `offset` parameter and some checks
    /// that I needed to remove.
    fn read_return_values(&mut self, offset: usize) -> PyResult<()> {
        let mut pointer = (self.inner.vm.get_ap() - offset).unwrap();
        for builtin_name in self.builtins.iter().rev() {
            if let Some(builtin_runner) =
                self.inner.vm.builtin_runners.iter_mut().find(|b| b.name() == *builtin_name)
            {
                let new_pointer =
                    builtin_runner.final_stack(&self.inner.vm.segments, pointer).map_err(|e| {
                        PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                    })?;
                pointer = new_pointer;
            } else {
                if !self.allow_missing_builtins {
                    return Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!(
                        "Missing builtin: {}",
                        builtin_name
                    )));
                }
                pointer.offset = pointer.offset.saturating_sub(1);

                if !self
                    .inner
                    .vm
                    .get_integer(pointer)
                    .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?
                    .is_zero()
                {
                    return Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!(
                        "Missing builtin stop ptr not zero: {}",
                        builtin_name
                    )));
                }
            }
        }
        Ok(())
    }
}
