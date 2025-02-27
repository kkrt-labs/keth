use std::{cell::RefCell, collections::HashMap, rc::Rc};

use crate::vm::program::PyProgram;
use cairo_vm::{
    hint_processor::builtin_hint_processor::dict_manager::DictManager,
    serde::deserialize_program::Identifier,
    types::{
        builtin_name::BuiltinName,
        relocatable::{MaybeRelocatable, Relocatable},
    },
    vm::{
        errors::vm_exception::VmException,
        runners::{builtin_runner::BuiltinRunner, cairo_runner::CairoRunner as RustCairoRunner},
        security::verify_secure_runner,
    },
};
use polars::prelude::*;
use pyo3::prelude::*;
use pyo3_polars::PyDataFrame;

use crate::vm::{
    layout::PyLayout, maybe_relocatable::PyMaybeRelocatable, relocatable::PyRelocatable,
    relocated_trace::PyRelocatedTraceEntry, run_resources::PyRunResources,
};
use num_traits::Zero;

use super::{
    dict_manager::PyDictManager, hints::HintProcessor, memory_segments::PyMemorySegmentManager,
};

#[pyclass(name = "CairoRunner", unsendable)]
pub struct PyCairoRunner {
    inner: RustCairoRunner,
    allow_missing_builtins: bool,
    builtins: Vec<BuiltinName>,
}

#[pymethods]
impl PyCairoRunner {
    #[new]
    #[pyo3(signature = (program, layout=None, proof_mode=false, allow_missing_builtins=false))]
    fn new(
        program: &PyProgram,
        layout: Option<PyLayout>,
        proof_mode: bool,
        allow_missing_builtins: bool,
    ) -> PyResult<Self> {
        let layout = layout.unwrap_or_default().into_layout_name()?;

        let mut inner = RustCairoRunner::new(
            &program.inner,
            layout,
            None, // dynamic_layout_params
            proof_mode,
            true, // trace_enabled
            true, // disable_trace_padding
        )
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        let dict_manager = DictManager::new();
        inner.exec_scopes.insert_value("dict_manager", Rc::new(RefCell::new(dict_manager)));
        let identifiers = program
            .inner
            .iter_identifiers()
            .map(|(name, identifier)| (name.to_string(), identifier.clone()))
            .collect::<HashMap<String, Identifier>>();

        // Insert the program identifiers in the exec_scopes, so that we're able to pull identifier
        // data when executing hints
        inner.exec_scopes.insert_value("__program_identifiers__", identifiers);

        Ok(Self {
            inner,
            allow_missing_builtins,
            builtins: program.inner.iter_builtins().copied().collect(),
        })
    }

    /// Initialize the runner program_base, execution_base and builtins segments.
    pub fn initialize_segments(&mut self) -> PyResult<()> {
        self.inner
            .initialize_builtins(self.allow_missing_builtins)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        self.inner.initialize_segments(None);

        Ok(())
    }

    /// Initialize the runner with the given stack and entrypoint offset.
    #[pyo3(signature = (stack, entrypoint, ordered_builtins=None))]
    pub fn initialize_vm(
        &mut self,
        stack: Vec<PyMaybeRelocatable>,
        entrypoint: usize,
        ordered_builtins: Option<Vec<String>>,
    ) -> PyResult<PyRelocatable> {
        let initial_stack = self.builtins_stack(ordered_builtins)?;
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
    fn fp(&self) -> PyRelocatable {
        PyRelocatable { inner: self.inner.vm.get_fp() }
    }

    #[getter]
    fn pc(&self) -> PyRelocatable {
        PyRelocatable { inner: self.inner.vm.get_pc() }
    }

    #[getter]
    fn segments(&mut self) -> PyMemorySegmentManager {
        PyMemorySegmentManager { vm: &mut self.inner.vm }
    }

    #[getter]
    fn dict_manager(&self) -> PyResult<PyDictManager> {
        let dict_manager = self
            .inner
            .exec_scopes
            .get_dict_manager()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(PyDictManager { inner: dict_manager })
    }

    fn run_until_pc(&mut self, address: PyRelocatable, resources: PyRunResources) -> PyResult<()> {
        let mut hint_processor =
            HintProcessor::default().with_run_resources(resources.inner).build();

        self.inner
            .run_until_pc(address.inner, &mut hint_processor)
            .map_err(|e| VmException::from_vm_error(&self.inner, e))
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

    fn relocate(&mut self) -> PyResult<()> {
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

    #[getter]
    fn trace_df(&self) -> PyResult<PyDataFrame> {
        let relocated_trace = self.inner.relocated_trace.clone().unwrap_or_default();
        let trace_len = relocated_trace.len();
        let mut pc_values = Vec::with_capacity(trace_len);
        let mut ap_values = Vec::with_capacity(trace_len);
        let mut fp_values = Vec::with_capacity(trace_len);

        for entry in relocated_trace.iter() {
            pc_values.push(entry.pc as u64);
            ap_values.push(entry.ap as u64);
            fp_values.push(entry.fp as u64);
        }

        let df = df!("pc" => pc_values, "ap" => ap_values, "fp" => fp_values)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        Ok(PyDataFrame(df))
    }
}

impl PyCairoRunner {
    fn builtins_stack(
        &mut self,
        ordered_builtins: Option<Vec<String>>,
    ) -> PyResult<Vec<MaybeRelocatable>> {
        let mut stack = Vec::new();
        let builtin_runners =
            self.inner.vm.builtin_runners.iter().map(|b| (b.name(), b)).collect::<HashMap<_, _>>();

        if let Some(names) = ordered_builtins {
            self.builtins = names
                .iter()
                .map(|name| {
                    BuiltinName::from_str_with_suffix(name).ok_or_else(|| {
                        PyErr::new::<pyo3::exceptions::PyValueError, _>(format!(
                            "Invalid builtin name: {}",
                            name
                        ))
                    })
                })
                .collect::<PyResult<Vec<_>>>()?;
        };
        for builtin_name in self.builtins.iter() {
            if let Some(builtin_runner) = builtin_runners.get(builtin_name) {
                stack.append(&mut builtin_runner.initial_stack());
            } else {
                return Err(PyErr::new::<pyo3::exceptions::PyValueError, _>(format!(
                    "Builtin runner {} not found",
                    builtin_name
                )));
            }
        }
        Ok(stack)
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
