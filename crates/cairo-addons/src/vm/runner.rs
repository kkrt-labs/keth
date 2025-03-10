use super::{
    dict_manager::PyDictManager, hints::HintProcessor, memory_segments::PyMemorySegmentManager,
};
use crate::vm::{
    layout::PyLayout, maybe_relocatable::PyMaybeRelocatable, program::PyProgram,
    relocatable::PyRelocatable, run_resources::PyRunResources,
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
    /// The builtins, ordered as they're defined in the program entrypoint.
    ordered_builtins: Vec<BuiltinName>,
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
    #[pyo3(signature = (program, py_identifiers=None, layout=None, proof_mode=false, allow_missing_builtins=false, enable_pythonic_hints=false, ordered_builtins=vec![]))]
    fn new(
        program: &PyProgram,
        py_identifiers: Option<PyObject>,
        layout: Option<PyLayout>,
        proof_mode: bool,
        allow_missing_builtins: bool,
        enable_pythonic_hints: bool,
        ordered_builtins: Vec<String>,
    ) -> PyResult<Self> {
        let layout = layout.unwrap_or_default().into_layout_name()?;

        let ordered_builtin_names = ordered_builtins
            .iter()
            .map(|name| BuiltinName::from_str(name.strip_suffix("_ptr").unwrap()).unwrap())
            .collect();

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
                ordered_builtins: ordered_builtin_names,
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
            ordered_builtins: ordered_builtin_names,
            enable_pythonic_hints,
        })
    }

    /// Initializes the runner's segments, including program_base, execution_base, and all builtins.
    /// In proof mode, this initializes all builtins of the layout, even those not used by the
    /// program.
    pub fn initialize_segments(&mut self) -> PyResult<()> {
        // Note: in proof mode, this initializes __all__ builtins of the layout.
        self.inner
            .initialize_builtins(self.allow_missing_builtins)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        self.inner.initialize_segments(None);

        Ok(())
    }

    /// Initializes the VM, preparing it for execution.
    /// Sets up the zero segment for modulo operations and initializes the VM's internal state.
    pub fn initialize_vm(&mut self) -> PyResult<()> {
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

    /// Loads data into memory at the specified base address.
    ///
    /// # Arguments
    /// * `base` - The base address where data will be loaded
    /// * `data` - The data to load into memory
    fn load_data(&mut self, base: PyRelocatable, data: Vec<PyMaybeRelocatable>) -> PyResult<()> {
        let data: Vec<MaybeRelocatable> = data.into_iter().map(|x| x.into()).collect();
        self.inner
            .vm
            .load_data(base.inner, &data)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }

    /// Loads the program data into memory at the specified base address.
    /// Uses a raw pointer to avoid borrow checker issues with the program data.
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
    fn dict_manager(&self) -> PyResult<PyDictManager> {
        let dict_manager = self
            .inner
            .exec_scopes
            .get_dict_manager()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(PyDictManager { inner: dict_manager })
    }

    /// Returns a dictionary of builtin runners with their state information.
    /// For each builtin, includes whether it's included in the program, its base address,
    /// name, initial stack, and final stack (for unused builtins).
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

    /// Runs the VM until the program counter reaches the specified address.
    ///
    /// # Arguments
    /// * `address` - The target address to run until
    /// * `resources` - Resources limiting the execution (e.g., max steps)
    ///
    /// Uses our own hint processor to handle Cairo hints during execution.
    /// This hint processor can support pythonic hints execution (if enabled).
    /// Ends the run after reaching the target address. If in proof mode this will loop on `jmp rel
    /// 0` until the steps is a power of 2.
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

    /// Reads return values from the stack, starting at the specified offset from ap.
    /// Processes builtin pointers in reverse order to construct the final return value.
    fn read_return_values(&mut self, offset: usize) -> PyResult<PyRelocatable> {
        let pointer = self._read_return_values(offset)?;
        Ok(PyRelocatable { inner: pointer })
    }

    fn verify_secure_runner(&mut self) -> PyResult<()> {
        verify_secure_runner(&self.inner, true, None)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }

    /// Relocates all memory segments to their final positions.
    /// This is required after execution to get the final memory layout.
    fn relocate(&mut self) -> PyResult<()> {
        self.inner
            .relocate(true)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }

    /// Returns the execution trace as a Polars DataFrame.
    /// The DataFrame contains columns for pc, ap, and fp values at each step.
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

    #[getter]
    fn fp(&self) -> PyRelocatable {
        PyRelocatable { inner: self.inner.vm.get_fp() }
    }

    #[getter]
    fn pc(&self) -> PyRelocatable {
        PyRelocatable { inner: self.inner.vm.get_pc() }
    }

    /// Updates the execution public memory with return data offsets.
    ///
    /// # Arguments
    /// * `pointer` - The pointer to the return data
    /// * `first_return_data_offset` - The offset of the first return data value
    ///
    /// This is required for proof mode to include return values in the public memory.
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

    /// Writes the execution trace to a binary file.
    /// Used in proof mode to generate input for the prover.
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

    /// Writes the memory contents to a binary file.
    /// Used in proof mode to generate input for the prover.
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

    /// Writes the AIR public input to a JSON file.
    /// Contains public information needed for proof verification.
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

    /// Writes the AIR private input to a JSON file.
    ///
    /// # Arguments
    /// * `trace_path` - Path to the trace file
    /// * `memory_path` - Path to the memory file
    /// * `file_path` - Path where the AIR private input will be written
    ///
    /// Contains private information needed for proof generation.
    fn write_binary_air_private_input(
        &self,
        trace_path: PathBuf,
        memory_path: PathBuf,
        file_path: String,
    ) -> PyResult<()> {
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
}

impl PyCairoRunner {
    /// Internal implementation of read_return_values with additional checks.
    /// Processes builtin pointers in reverse order and handles missing builtins.
    fn _read_return_values(&mut self, offset: usize) -> PyResult<Relocatable> {
        let mut pointer = (self.inner.vm.get_ap() - offset).unwrap();
        println!("Ordered builtins: {:?}", self.ordered_builtins);
        for builtin_name in self.ordered_builtins.iter().rev() {
            if let Some(builtin_runner) =
                self.inner.vm.builtin_runners.iter_mut().find(|b| b.name() == *builtin_name)
            {
                println!("Getting final stack for {}", builtin_name);
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
