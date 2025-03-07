use std::{cell::RefCell, collections::HashMap, rc::Rc};

use crate::vm::{
    layout::PyLayout, maybe_relocatable::PyMaybeRelocatable, program::PyProgram,
    relocatable::PyRelocatable, relocated_trace::PyRelocatedTraceEntry,
    run_resources::PyRunResources,
};
use bincode::enc::write::SliceWriter;
use cairo_vm::{
    cairo_run::write_encoded_trace,
    hint_processor::builtin_hint_processor::dict_manager::DictManager,
    serde::deserialize_program::Identifier,
    types::{
        builtin_name::BuiltinName,
        relocatable::{MaybeRelocatable, Relocatable},
    },
    vm::{
        errors::{runner_errors::RunnerError, vm_exception::VmException},
        runners::{builtin_runner::BuiltinRunner, cairo_runner::CairoRunner as RustCairoRunner},
        security::verify_secure_runner,
    },
};
use num_traits::Zero;
use polars::prelude::*;
use pyo3::{
    prelude::*,
    types::{IntoPyDict, PyDict},
};
use pyo3_polars::PyDataFrame;
use std::ffi::CString;

use super::{
    dict_manager::PyDictManager, hints::HintProcessor, memory_segments::PyMemorySegmentManager,
};

#[pyclass(name = "CairoRunner", unsendable)]
pub struct PyCairoRunner {
    inner: RustCairoRunner,
    allow_missing_builtins: bool,
    builtins: Vec<BuiltinName>,
    enable_pythonic_hints: bool,
}

#[pymethods]
impl PyCairoRunner {
    /// Initialize the runner with the given program and identifiers.
    /// # Arguments
    /// * `program` - The _rust_ program to run.
    /// * `py_identifiers` - The _pythonic_ identifiers for this program.
    /// * `layout` - The layout to use for the runner.
    /// * `proof_mode` - Whether to run in proof mode.
    /// * `allow_missing_builtins` - Whether to allow missing builtins.
    #[new]
    #[pyo3(signature = (program, py_identifiers=None, layout=None, proof_mode=false, allow_missing_builtins=false, enable_pythonic_hints=false))]
    fn new(
        program: &PyProgram,
        py_identifiers: Option<PyObject>,
        layout: Option<PyLayout>,
        proof_mode: bool,
        allow_missing_builtins: bool,
        enable_pythonic_hints: bool,
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

        if !enable_pythonic_hints || !cfg!(feature = "pythonic-hints") {
            return Ok(Self {
                inner,
                allow_missing_builtins,
                builtins: program.inner.iter_builtins().copied().collect(),
                enable_pythonic_hints,
            });
        }

        // Add context variables required for pythonic hint execution

        let identifiers = program
            .inner
            .iter_identifiers()
            .map(|(name, identifier)| (name.to_string(), identifier.clone()))
            .collect::<HashMap<String, Identifier>>();

        // Insert the _rust_ program_identifiers in the exec_scopes, so that we're able to pull
        // identifier data when executing hints to build VmConsts.
        inner.exec_scopes.insert_value("__program_identifiers__", identifiers);

        // Initialize a python context object that will be accessible throughout the execution of
        // all hints.
        // This enables us to directly use the Python identifiers passed in, avoiding the need to
        // serialize and deserialize the program JSON.
        Python::with_gil(|py| {
            let context = PyDict::new(py);

            if let Some(py_identifiers) = py_identifiers {
                // Store the Python identifiers directly in the context
                context.set_item("py_identifiers", py_identifiers).map_err(|e| {
                    PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                })?;
            }

            // Import and run the initialization code from the injected module
            let setup_code = r#"
try:
    from cairo_addons.hints.injected import prepare_context
    prepare_context(lambda: globals())
except Exception as e:
    print(f"Warning: Error during initialization: {e}")
"#;

            // Run the initialization code
            py.run(&CString::new(setup_code)?, Some(&context), None).map_err(|e| {
                PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!(
                    "Failed to initialize Python globals: {}",
                    e
                ))
            })?;

            // Store the context object, modified in the initialization code, in the exec_scopes
            // to access it throughout the execution of hints
            let unbounded_context: Py<PyDict> = context.into_py_dict(py)?.into();
            inner.exec_scopes.insert_value("__context__", unbounded_context);
            Ok::<(), PyErr>(())
        })?;

        Ok(Self {
            inner,
            allow_missing_builtins,
            builtins: program.inner.iter_builtins().copied().collect(),
            enable_pythonic_hints,
        })
    }

    /// Initialize the runner program_base, execution_base and builtins segments.
    pub fn initialize_segments(&mut self) -> PyResult<()> {
        // Note: in proof mode, this initializes __all__ builtins of the layout.
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
        let stack: Vec<MaybeRelocatable> = initial_stack
            .into_iter()
            .chain(stack.into_iter().map(|x| x.into()))
            .collect::<Vec<_>>();

        // canonical offset should be 2 for Cairo 0
        let target_offset: usize = 2;
        let execution_base = self.inner.execution_base.ok_or(RunnerError::NoExecBase).unwrap();
        let return_fp = Into::<MaybeRelocatable>::into((execution_base + target_offset).unwrap());
        let end = ((self.inner.program_base.unwrap() +
            self.inner.get_program().shared_program_data.data.len())
        .unwrap() -
            2)
        .unwrap();
        println!("end: {:?}", end);
        // stack = [return_fp, end] + stack + [return_fp, end]
        let mut stack_with_prefix = vec![return_fp.clone(), end.into()];
        stack_with_prefix.extend(stack.clone());
        stack_with_prefix.extend(vec![return_fp, end.into()]);
        self.inner.execution_public_memory = Some(Vec::from_iter(0..stack_with_prefix.len()));
        println!("stack_with_prefix: {:?}", stack_with_prefix);

        self.inner.initial_pc = Some((self.inner.program_base.unwrap() + entrypoint).unwrap());
        //TODO: cloning here is bad but i don't know how to do it otherwise
        let program = self.inner.get_program().shared_program_data.data.clone();
        self.inner.vm.load_data(self.inner.program_base.unwrap(), &program).unwrap();
        // // Mark all addresses from the program segment as accessed
        // for i in 0..self.inner.get_program().shared_program_data.data.len() {
        //     self.inner.vm.segments.memory.mark_as_accessed((self.inner.program_base.unwrap() +
        // i).unwrap()); }

        self.inner.vm.load_data(self.inner.execution_base.unwrap(), &stack_with_prefix).unwrap();

        self.inner.initial_fp =
            Some((self.inner.execution_base.unwrap() + stack_with_prefix.len()).unwrap());
        self.inner.initial_ap = self.inner.initial_fp;
        // self.inner.final_pc = Some(end);

        println!(
            "initial ap, pc, fp: {:?}, {:?}, {:?}",
            self.inner.initial_ap, self.inner.initial_pc, self.inner.initial_fp
        );
        println!("final pc: {:?}", self.inner.final_pc);

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

    #[pyo3(signature = (address, resources))]
    fn run_until_pc(&mut self, address: PyRelocatable, resources: PyRunResources) -> PyResult<()> {
        let mut hint_processor = if self.enable_pythonic_hints {
            HintProcessor::default()
                .with_run_resources(resources.inner)
                .with_dynamic_python_hints()
                .build()
        } else {
            HintProcessor::default().with_run_resources(resources.inner).build()
        };

        self.inner
            .run_until_pc(address.inner, &mut hint_processor)
            .map_err(|e| VmException::from_vm_error(&self.inner, e))
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        self.inner
            .end_run(false, false, &mut hint_processor)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }

    fn verify_auto_deductions(&mut self) -> PyResult<()> {
        self.inner
            .vm
            .verify_auto_deductions()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        Ok(())
    }

    fn read_return_values(&mut self, offset: usize) -> PyResult<PyRelocatable> {
        PyResult::Ok(PyRelocatable { inner: self._read_return_values(offset)? })
    }

    fn verify_secure_runner(&mut self) -> PyResult<()> {
        verify_secure_runner(&self.inner, true, None)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        Ok(())
    }

    fn verify_and_relocate(&mut self, offset: usize) -> PyResult<()> {
        self.verify_auto_deductions()?;
        self.read_return_values(offset)?;
        self.verify_secure_runner()?;
        self.relocate()?;
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

    #[pyo3(signature = (pointer, first_return_data_offset))]
    fn update_execution_public_memory(
        &mut self,
        pointer: PyRelocatable,
        first_return_data_offset: usize,
    ) -> PyResult<()> {
        let exec_base = self.inner.execution_base.ok_or_else(|| {
            PyErr::new::<pyo3::exceptions::PyRuntimeError, _>("No execution base available")
        })?;

        // Calculate the range to add to execution_public_memory
        let begin = pointer.inner.offset - exec_base.offset;
        let ap = self.inner.vm.get_ap();
        let end = ap.offset - first_return_data_offset;

        // Extend execution_public_memory with this range
        self.inner
            .execution_public_memory
            .as_mut()
            .ok_or_else(|| {
                PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(
                    "No execution public memory available",
                )
            })?
            .extend(begin..end);

        Ok(())
    }

    #[pyo3(signature = (file_path))]
    fn write_binary_trace(&self, file_path: String) -> PyResult<()> {
        if let Some(relocated_trace) = &self.inner.relocated_trace {
            use std::{fs::File, io::Write};

            let mut buffer = Vec::new();
            let mut writer = SliceWriter::new(&mut buffer);
            write_encoded_trace(relocated_trace, &mut writer)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
            let mut file = File::create(file_path)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
            file.write_all(&buffer)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
            Ok(())
        } else {
            Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>("No relocated trace available"))
        }
    }

    #[getter]
    fn builtin_runners(&self) -> PyResult<PyObject> {
        Python::with_gil(|py| {
            let dict = PyDict::new(py);

            for builtin_runner in self.inner.vm.builtin_runners.iter() {
                let name = builtin_runner.name().to_string();
                let included = builtin_runner.included();
                let base = PyRelocatable {
                    inner: Relocatable { segment_index: builtin_runner.base() as isize, offset: 0 },
                };

                let runner_dict = PyDict::new(py);
                runner_dict.set_item("included", included)?;
                runner_dict.set_item("base", base)?;
                runner_dict.set_item("name", name.clone())?;

                dict.set_item(name, runner_dict)?;
            }

            Ok(dict.into())
        })
    }
}

impl PyCairoRunner {
    fn builtins_stack(
        &mut self,
        ordered_builtins: Option<Vec<String>>,
    ) -> PyResult<Vec<MaybeRelocatable>> {
        let ordered_builtins = ordered_builtins.unwrap_or_default();

        let mut stack = Vec::new();
        let mut used_builtins_acc = Vec::new();

        // # If we're in proof mode, all builtins are enabled by default. However, we don't use them
        // in the entrypoint, nor do we return them at the end of the execution.
        // # Because they're unused, we can simply put them in the stack (no impact on program
        // execution), which is dumped into the execution public memory. # Note: if we tried
        // to pass an included builtin here, it would fail, because we would try to access ptr-1
        // which is an invalid address. (see final_stack)
        for builtin_runner in self.inner.vm.builtin_runners.iter_mut() {
            let runner_base =
                Relocatable { segment_index: builtin_runner.base() as isize, offset: 0 };
            let is_included =
                ordered_builtins.contains(&builtin_runner.name().to_str_with_suffix().to_string());
            if !is_included {
                let final_pointer =
                    builtin_runner.final_stack(&self.inner.vm.segments, runner_base).unwrap();
                stack.push(final_pointer.into());
            } else {
                used_builtins_acc.push(builtin_runner);
            }
        }

        for builtin_runner in used_builtins_acc.iter() {
            stack.append(&mut builtin_runner.initial_stack());
        }

        Ok(stack)
    }

    /// Mainly like `CairoRunner::read_return_values` but with an `offset` parameter and some checks
    /// that I needed to remove.
    fn _read_return_values(&mut self, offset: usize) -> PyResult<Relocatable> {
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
        Ok(pointer)
    }
}
