use super::{
    dict_manager::PyDictManager, hints::HintProcessor, memory_segments::PyMemorySegmentManager,
};
use crate::vm::{
    layout::PyLayout, maybe_relocatable::PyMaybeRelocatable, program::PyProgram,
    relocatable::PyRelocatable, relocated_trace::PyRelocatedTraceEntry,
    run_resources::PyRunResources,
};
use bincode::enc::write::Writer;
use cairo_vm::{
    cairo_run::{write_encoded_memory, write_encoded_trace},
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
use num_traits::Zero;
use polars::prelude::*;
use pyo3::{
    prelude::*,
    types::{IntoPyDict, PyDict},
};
use pyo3_polars::PyDataFrame;
use std::{
    cell::RefCell,
    collections::HashMap,
    ffi::CString,
    io::{self, Write},
    path::PathBuf,
    rc::Rc,
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
    #[pyo3(signature = (stack, entrypoint))]
    pub fn initialize_vm(
        &mut self,
        stack: Vec<PyMaybeRelocatable>,
        entrypoint: usize,
    ) -> PyResult<()> {
        // let stack: Vec<MaybeRelocatable> = stack.into_iter().map(|x| x.into()).collect();

        // // canonical offset for proof mode in cairo 0
        // let target_offset: usize = 2;
        // let execution_base = self
        //     .inner
        //     .execution_base
        //     .ok_or(RunnerError::NoExecBase)
        //     .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        // let return_fp = (execution_base + target_offset).unwrap();
        // let end = ((self.inner.program_base.unwrap() +
        //     self.inner.get_program().shared_program_data.data.len())
        // .unwrap() -
        //     target_offset)
        //     .unwrap();

        // let mut stack_with_prefix: Vec<MaybeRelocatable> =
        //     vec![return_fp.clone().into(), end.into()];
        // stack_with_prefix.extend(stack);
        // stack_with_prefix.extend(vec![return_fp.clone().into(), end.into()]);
        // self.inner.execution_public_memory = Some(Vec::from_iter(0..stack_with_prefix.len()));

        // self.inner.initial_pc = Some((self.inner.program_base.unwrap() + entrypoint).unwrap());
        // let program = self.inner.get_program().shared_program_data.data.clone();
        // self.inner
        //     .vm
        //     .load_data(self.inner.program_base.unwrap(), &program)
        //     .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        // // // Mark all addresses from the program segment as accessed
        // // for i in 0..self.inner.get_program().shared_program_data.data.len() {
        // //     self.inner.vm.segments.memory.mark_as_accessed((self.inner.program_base.unwrap() +
        // // i).unwrap()); }
        // self.inner
        //     .vm
        //     .load_data(self.inner.execution_base.unwrap(), &stack_with_prefix)
        //     .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        // self.inner.initial_fp = Some((execution_base + stack_with_prefix.len()).unwrap());
        // self.inner.initial_ap = self.inner.initial_fp;

        for builtin_runner in self.inner.vm.builtin_runners.iter_mut() {
            if let BuiltinRunner::Mod(runner) = builtin_runner {
                runner.initialize_zero_segment(&mut self.inner.vm.segments);
            }
        }
        self.inner
            .initialize_vm()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        Ok(())
    }

    #[getter]
    fn initial_pc(&self) -> Option<PyRelocatable> {
        self.inner.initial_pc.map(|x| PyRelocatable { inner: x })
    }

    #[setter]
    fn set_initial_pc(&mut self, value: Option<PyRelocatable>) {
        self.inner.initial_pc = value.map(|x| x.inner);
    }

    #[getter]
    fn initial_ap(&self) -> Option<PyRelocatable> {
        self.inner.initial_ap.map(|x| PyRelocatable { inner: x })
    }

    #[setter]
    fn set_initial_ap(&mut self, value: Option<PyRelocatable>) {
        self.inner.initial_ap = value.map(|x| x.inner);
    }

    #[getter]
    fn initial_fp(&self) -> Option<PyRelocatable> {
        self.inner.initial_fp.map(|x| PyRelocatable { inner: x })
    }

    #[setter]
    fn set_initial_fp(&mut self, value: Option<PyRelocatable>) {
        self.inner.initial_fp = value.map(|x| x.inner);
    }

    #[getter]
    fn program_base(&self) -> Option<PyRelocatable> {
        self.inner.program_base.map(|x| PyRelocatable { inner: x })
    }

    #[setter]
    fn set_program_base(&mut self, value: Option<PyRelocatable>) {
        self.inner.program_base = value.map(|x| x.inner);
    }

    #[getter]
    fn execution_base(&self) -> Option<PyRelocatable> {
        self.inner.execution_base.map(|x| PyRelocatable { inner: x })
    }

    #[setter]
    fn set_execution_base(&mut self, value: Option<PyRelocatable>) {
        self.inner.execution_base = value.map(|x| x.inner);
    }

    #[getter]
    fn execution_public_memory(&self) -> Option<Vec<usize>> {
        self.inner.execution_public_memory.clone()
    }

    #[setter]
    fn set_execution_public_memory(&mut self, value: Option<Vec<usize>>) {
        self.inner.execution_public_memory = value;
    }

    #[getter]
    fn segments(&mut self) -> PyMemorySegmentManager {
        PyMemorySegmentManager { vm: &mut self.inner.vm }
    }

    fn load_data(&mut self, base: PyRelocatable, data: Vec<PyMaybeRelocatable>) -> PyResult<()> {
        let data: Vec<MaybeRelocatable> = data.into_iter().map(|x| x.into()).collect();
        self.inner
            .vm
            .load_data(base.inner, &data)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }

    fn load_program_data(&mut self, base: PyRelocatable) -> PyResult<()> {
        // Avoid borrow-checker issues by using a raw pointer to the data.
        let program = self.inner.get_program();
        let data_ptr = &program.shared_program_data.data as *const Vec<_>; // Raw pointer to data
        let data = unsafe { &*data_ptr }; // Dereference as immutable reference (no mutation yet)
        self.inner
            .vm
            .load_data(base.inner, data)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }

    #[getter]
    fn program_len(&self) -> usize {
        self.inner.get_program().shared_program_data.data.len()
    }

    #[getter]
    fn program(&self) -> PyResult<PyProgram> {
        Ok(PyProgram { inner: self.inner.get_program().clone() })
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
    #[getter]
    fn builtin_runners(&mut self) -> PyResult<PyObject> {
        let ap = self.inner.vm.get_ap();
        Python::with_gil(|py| {
            let dict = PyDict::new(py);
            for builtin_runner in self.inner.vm.builtin_runners.iter_mut() {
                let name = builtin_runner.name().to_string();
                let included = builtin_runner.included();
                let initial_stack: Vec<PyRelocatable> = builtin_runner
                    .initial_stack()
                    .into_iter()
                    .map(|x| PyRelocatable { inner: x.try_into().unwrap() })
                    .collect();
                let final_stack: Vec<PyRelocatable> = if !included {
                    builtin_runner
                        .final_stack(&self.inner.vm.segments, ap)
                        .into_iter()
                        .map(|x| PyRelocatable { inner: x })
                        .collect()
                } else {
                    vec![]
                };
                let base = PyRelocatable {
                    inner: Relocatable { segment_index: builtin_runner.base() as isize, offset: 0 },
                };
                let runner_dict = PyDict::new(py);
                runner_dict.set_item("included", included)?;
                runner_dict.set_item("base", base)?;
                runner_dict.set_item("name", name.clone())?;
                runner_dict.set_item("initial_stack", initial_stack)?;
                runner_dict.set_item("final_stack", final_stack)?;
                dict.set_item(name, runner_dict)?;
            }
            Ok(dict.into())
        })
    }

    // Existing run_until_pc (unchanged)
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

    // New methods for post-run processing
    fn verify_auto_deductions(&mut self) -> PyResult<()> {
        self.inner
            .vm
            .verify_auto_deductions()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }

    fn read_return_values(&mut self, offset: usize) -> PyResult<PyRelocatable> {
        let pointer = self._read_return_values(offset)?;
        Ok(PyRelocatable { inner: pointer })
    }

    fn verify_secure_runner(&mut self) -> PyResult<()> {
        verify_secure_runner(&self.inner, true, None)
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

    #[getter]
    fn ap(&self) -> PyRelocatable {
        PyRelocatable { inner: self.inner.vm.get_ap() }
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
        let begin = pointer.inner.offset - exec_base.offset;
        let ap = self.inner.vm.get_ap();
        let end = ap.offset - first_return_data_offset;
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

    fn finalize_segments(&mut self) -> PyResult<()> {
        self.inner
            .finalize_segments()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }

    // def write_binary_trace(trace_file: IO[bytes], trace: List[TraceEntry[int]]):
    // for trace_entry in trace:
    //     trace_file.write(trace_entry.serialize())
    // trace_file.flush()
    fn write_binary_trace(&self, file_path: String) -> PyResult<()> {
        if let Some(trace_entries) = &self.inner.relocated_trace {
            let trace_file = std::fs::File::create(file_path)?;
            let mut trace_writer =
                FileWriter::new(io::BufWriter::with_capacity(3 * 1024 * 1024, trace_file));

            write_encoded_trace(trace_entries, &mut trace_writer)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
            Ok(())
        } else {
            Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>("No relocated trace available"))
        }
    }

    fn write_binary_memory(&self, file_path: String, capacity: usize) -> PyResult<()> {
        let memory_file = std::fs::File::create(file_path)?;
        let mut memory_writer =
            FileWriter::new(io::BufWriter::with_capacity(capacity, memory_file));

        write_encoded_memory(&self.inner.relocated_memory, &mut memory_writer)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
        memory_writer
            .flush()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
        Ok(())
    }

    fn write_binary_air_public_input(&self, file_path: String) -> PyResult<()> {
        let json = self
            .inner
            .get_air_public_input()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?
            .serialize_json()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        std::fs::write(file_path, json)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
        Ok(())
    }

    fn write_binary_air_private_input(
        &self,
        trace_path: PathBuf,
        memory_path: PathBuf,
        file_path: String,
    ) -> PyResult<()> {
        // Get absolute paths of trace_file & memory_file
        let trace_path = trace_path
            .as_path()
            .canonicalize()
            .unwrap_or(trace_path.clone())
            .to_string_lossy()
            .to_string();
        let memory_path = memory_path
            .as_path()
            .canonicalize()
            .unwrap_or(memory_path.clone())
            .to_string_lossy()
            .to_string();

        let json = self
            .inner
            .get_air_private_input()
            .to_serializable(trace_path, memory_path)
            .serialize_json()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        std::fs::write(file_path, json)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyIOError, _>(e.to_string()))?;
        Ok(())
    }

    // fn get_perm_range_check_limits(&self) -> PyResult<(i128, i128)> {
    //     let (rc_min, rc_max) = self
    //         .inner
    //         .get_perm_range_check_limits()
    //         .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
    //     Ok((rc_min, rc_max))
    // }

    // #[getter]
    // fn relocated_memory(&self) -> PyResult<HashMap<usize, PyMaybeRelocatable>> {
    //     let memory = self.inner.relocated_memory.as_ref().ok_or_else(|| {
    //         PyErr::new::<pyo3::exceptions::PyRuntimeError, _>("No relocated memory available")
    //     })?;
    //     let result =
    //         memory.iter().map(|(k, v)| (k.clone(),
    // PyMaybeRelocatable::from(v.clone()))).collect();     Ok(result)
    // }

    // fn get_public_memory_addresses(&self) -> PyResult<Vec<usize>> {
    //     let offsets = self
    //         .inner
    //         .get_segment_offsets()
    //         .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
    //     let addresses = self
    //         .inner
    //         .segments
    //         .get_public_memory_addresses(&offsets)
    //         .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
    //     Ok(addresses)
    // }

    // fn get_memory_segment_addresses(&self) -> PyResult<HashMap<usize, (usize, usize)>> {
    //     let addresses = self
    //         .inner
    //         .get_memory_segment_addresses()
    //         .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
    //     Ok(addresses)
    // }

    // fn get_air_private_input(&self) -> PyResult<HashMap<String, PyObject>> {
    //     let private_input = self
    //         .inner
    //         .get_air_private_input()
    //         .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
    //     Python::with_gil(|py| {
    //         let dict = PyDict::new(py);
    //         for (k, v) in private_input.into_iter() {
    //             dict.set_item(k, v.to_object(py))?;
    //         }
    //         Ok(dict.into())
    //     })
    // }
}

impl PyCairoRunner {
    /// Mainly like `CairoRunner::read_return_values` but with an `offset` parameter and some checks
    /// that I needed to remove.
    fn _read_return_values(&mut self, offset: usize) -> PyResult<Relocatable> {
        let mut pointer = (self.inner.vm.get_ap() - offset).unwrap();
        for builtin_name in self.builtins.iter().rev() {
            if let Some(builtin_runner) =
                self.inner.vm.builtin_runners.iter_mut().find(|b| b.name() == *builtin_name)
            {
                pointer =
                    builtin_runner.final_stack(&self.inner.vm.segments, pointer).map_err(|e| {
                        PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                    })?;
            } else if !self.allow_missing_builtins {
                return Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!(
                    "Missing builtin: {}",
                    builtin_name
                )));
            } else {
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

// From <https://github.com/lambdaclass/cairo-vm/blob/5d7c20880785e1f9edbd73d0d46aeb58d8bced4e/cairo-vm-cli/src/main.rs#L109-L140>
struct FileWriter {
    buf_writer: io::BufWriter<std::fs::File>,
    bytes_written: usize,
}

impl Writer for FileWriter {
    fn write(&mut self, bytes: &[u8]) -> Result<(), bincode::error::EncodeError> {
        self.buf_writer
            .write_all(bytes)
            .map_err(|e| bincode::error::EncodeError::Io { inner: e, index: self.bytes_written })?;

        self.bytes_written += bytes.len();

        Ok(())
    }
}

impl FileWriter {
    fn new(buf_writer: io::BufWriter<std::fs::File>) -> Self {
        Self { buf_writer, bytes_written: 0 }
    }

    fn flush(&mut self) -> io::Result<()> {
        self.buf_writer.flush()
    }
}
