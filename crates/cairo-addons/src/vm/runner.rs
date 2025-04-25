use super::{
    dict_manager::PyDictManager, hints::HintProcessor, memory_segments::PyMemorySegmentManager,
    to_pyerr,
};
use crate::{
    stwo_bindings::prove_with_stwo,
    vm::{
        layout::PyLayout, maybe_relocatable::PyMaybeRelocatable, program::PyProgram,
        relocatable::PyRelocatable, run_resources::PyRunResources,
    },
};
use bincode::enc::write::Writer;
use cairo_vm::{
    cairo_run::{self, write_encoded_memory, write_encoded_trace, CairoRunConfig},
    hint_processor::builtin_hint_processor::dict_manager::DictManager,
    serde::deserialize_program::Identifier,
    types::{
        builtin_name::BuiltinName,
        exec_scope::ExecutionScopes,
        layout_name::LayoutName,
        program::Program,
        relocatable::{MaybeRelocatable, Relocatable},
    },
    vm::{
        errors::vm_exception::VmException,
        runners::{builtin_runner::BuiltinRunner, cairo_runner::CairoRunner as RustCairoRunner},
        security::verify_secure_runner,
    },
};
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
use tracing_subscriber::{filter::EnvFilter, fmt::format::FmtSpan};

// Names of implicit arguments that are pointers but not standard builtins handled by BuiltinRunner
const NON_BUILTIN_SEGMENT_PTR_NAMES: [&str; 2] = ["keccak_ptr", "blake2s_ptr"];

// Helper function to check if an argument name corresponds to a standard Cairo builtin
fn is_actual_builtin(arg_name: &str) -> bool {
    let name_without_ptr = arg_name.strip_suffix("_ptr").unwrap_or(arg_name);
    BuiltinName::from_str(name_without_ptr).is_some() &&
        !NON_BUILTIN_SEGMENT_PTR_NAMES.contains(&arg_name)
}

/// Represents the Cairo Virtual Machine runner, exposing its functionality to Python.
///
/// This struct wraps the Rust `CairoRunner` and provides Python bindings for its methods.
#[pyclass(name = "CairoRunner", unsendable)]
pub struct PyCairoRunner {
    inner: RustCairoRunner,
    allow_missing_builtins: bool,
    /// The return_data information (name, size) ordered as defined in the Cairo function
    /// signature.
    return_data_info: Vec<(String, Option<usize>)>,
    /// Whether to enable execution of hints containing logger.
    enable_traces: bool,
}

#[pymethods]
impl PyCairoRunner {
    /// Initialize the runner with the given program and identifiers.
    /// # Arguments
    /// * `program` - The _rust_ program to run.
    /// * `py_identifiers` - The _pythonic_ identifiers for this program. Only used when
    ///   enable_traces is true.
    /// * `layout` - The layout to use for the runner.
    /// * `proof_mode` - Whether to run in proof mode.
    /// * `allow_missing_builtins` - Whether to allow missing builtins.
    /// * `enable_traces` - Whether to enable execution of hints containing log traces. When false,
    ///   Python identifiers and program identifiers are not loaded to save memory and
    ///   initialization time.
    #[allow(clippy::too_many_arguments)]
    #[new]
    #[pyo3(signature = (program, py_identifiers=None, program_input=None, layout=None, proof_mode=false, allow_missing_builtins=false, enable_traces=false, return_data_info=vec![], cairo_file=None, py_debug_info=None))]
    fn new(
        program: &PyProgram,
        py_identifiers: Option<PyObject>,
        program_input: Option<PyObject>,
        layout: Option<PyLayout>,
        proof_mode: bool,
        allow_missing_builtins: bool,
        enable_traces: bool,
        return_data_info: Vec<(String, Option<usize>)>,
        cairo_file: Option<PyObject>,
        py_debug_info: Option<PyObject>,
    ) -> PyResult<Self> {
        let layout = layout.unwrap_or_default().into_layout_name()?;

        let mut inner = RustCairoRunner::new(
            &program.inner,
            layout,
            None, // dynamic_layout_params
            proof_mode,
            true,       // trace_enabled
            proof_mode, // disable_trace_padding can only be used in proof_mode
        )
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        let dict_manager = DictManager::new();
        inner.exec_scopes.insert_value("dict_manager", Rc::new(RefCell::new(dict_manager)));

        // Initialize a python context object that will be accessible throughout the execution of
        // all hints, but only load identifiers if logger is enabled
        Python::with_gil(|py| {
            let context = PyDict::new(py);

            let identifiers = program
                .inner
                .iter_identifiers()
                .map(|(name, identifier)| (name.to_string(), identifier.clone()))
                .collect::<HashMap<String, Identifier>>();

            // Insert the _rust_ program_identifiers in the exec_scopes, so that we're able to
            // pull identifier data when executing hints to build VmConsts.
            inner.exec_scopes.insert_value("__program_identifiers__", identifiers);

            if let Some(py_identifiers) = py_identifiers {
                // Store the Python identifiers directly in the context
                context.set_item("py_identifiers", py_identifiers).map_err(|e| {
                    PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                })?;
            }

            if let Some(program_input) = program_input {
                // Store the Python program input directly in the context
                context.set_item("program_input", program_input).map_err(|e| {
                    PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                })?;
            }

            if let Some(cairo_file) = cairo_file {
                context.set_item("cairo_file", cairo_file).map_err(|e| {
                    PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                })?;
            }

            if let Some(py_debug_info) = py_debug_info {
                context.set_item("py_debug_info", py_debug_info).map_err(|e| {
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

            // Store the context object in the exec_scopes regardless of logger status
            // This ensures the pythonic hint executor has a context to work with
            let unbounded_context: Py<PyDict> = context.into_py_dict(py)?.into();
            inner.exec_scopes.insert_value("__context__", unbounded_context);
            Ok::<(), PyErr>(())
        })?;

        Ok(Self { inner, allow_missing_builtins, return_data_info, enable_traces })
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
        PyMemorySegmentManager { inner: &mut self.inner.vm.segments }
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
    /// This hint processor always supports pythonic hints execution, but will
    /// skip hints containing "logger" when enable_traces is false for performance reasons.
    /// When enable_traces is false, Python identifiers and program identifiers are not loaded
    /// to save memory and initialization time.
    /// Ends the run after reaching the target address. If in proof mode this will loop on `jmp rel
    /// 0` until the steps is a power of 2.
    #[pyo3(signature = (address, resources))]
    fn run_until_pc(&mut self, address: PyRelocatable, resources: PyRunResources) -> PyResult<()> {
        let mut hint_processor = HintProcessor::default()
            .with_run_resources(resources.inner)
            .with_dynamic_python_hints(self.enable_traces)
            .build();
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
    fn read_return_values(&mut self) -> PyResult<PyRelocatable> {
        let pointer = self._read_return_values()?;
        Ok(PyRelocatable { inner: pointer })
    }

    fn verify_secure_runner(&mut self) -> PyResult<()> {
        verify_secure_runner(&self.inner, true, None)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        Ok(())
    }

    fn verify_squashed_dicts(&mut self) -> PyResult<()> {
        let dict_manager_ref = self
            .inner
            .exec_scopes
            .get_dict_manager()
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        let dict_manager = dict_manager_ref.borrow();

        let unsquashed_trackers: Vec<String> = dict_manager
            .trackers
            .values()
            .filter(|tracker| !tracker.is_squashed)
            .map(|t| t.name.clone().unwrap_or_else(|| t.current_ptr.to_string()))
            .collect();

        if !unsquashed_trackers.is_empty() {
            return Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!(
                "unsquashed trackers: {:?}",
                unsquashed_trackers
            )));
        }

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
    /// Processes builtin pointers and other implicit arguments in reverse order as they appear
    /// on the stack relative to the final `ap` register to calculate the starting pointer
    /// of the explicit return values.
    ///
    /// This method iterates through the `return_data_info` (which mirrors the function's
    /// implicit arguments and explicit return types) in reverse. For each argument, it determines
    /// its type (builtin, non-builtin segment pointer, or value) and adjusts the `pointer`
    /// accordingly based on the size consumed by that argument on the stack.
    ///
    /// Builtins have specific handling via `final_stack`. Non-builtin segment pointers
    /// (like `keccak_ptr`) are assumed to consume one felt (the pointer itself). Other implicit
    /// arguments passed by value consume their specified size (defaulting to 1 felt).
    ///
    ///
    /// # Returns
    /// The calculated `Relocatable` pointer pointing to the start of the explicit return values
    /// on the stack.
    ///
    /// # Errors
    /// Returns a `PyErr` if:
    /// - A required builtin is missing and `allow_missing_builtins` is false.
    /// - A missing builtin's stop pointer is non-zero when `allow_missing_builtins` is true.
    /// - An error occurs during memory access (e.g., getting the stop pointer value).
    fn _read_return_values(&mut self) -> PyResult<Relocatable> {
        let mut pointer = self.inner.vm.get_ap();
        // Iterate over all implicit arguments in reverse order as they appear on the stack
        for (arg_name, size) in self.return_data_info.iter().rev() {
            if is_actual_builtin(arg_name) {
                // Handle actual builtins
                let builtin_name_enum =
                    BuiltinName::from_str(arg_name.strip_suffix("_ptr").unwrap()).unwrap();
                if let Some(builtin_runner) =
                    self.inner.vm.builtin_runners.iter_mut().find(|b| b.name() == builtin_name_enum)
                {
                    pointer =
                        builtin_runner.final_stack(&self.inner.vm.segments, pointer).map_err(
                            |e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()),
                        )?;
                } else {
                    // Builtin is missing but allowed, check if its stop ptr is 0
                    // Assume it consumes 1 felt
                    pointer.offset = pointer.offset.saturating_sub(1);
                }
            } else {
                pointer.offset = pointer.offset.saturating_sub(size.unwrap_or(1));
            }
        }
        Ok(pointer)
    }
}

/// Initialize Cairo execution environment with the given program and inputs.
fn prepare_cairo_execution<'a>(
    entrypoint: &'a str,
    program_input: PyObject,
    compiled_program_path: &str,
) -> PyResult<(Program, ExecutionScopes, CairoRunConfig<'a>)> {
    let cairo_run_config: CairoRunConfig<'a> = CairoRunConfig {
        entrypoint: &entrypoint,
        trace_enabled: true,
        relocate_mem: true,
        layout: LayoutName::all_cairo,
        proof_mode: true,
        secure_run: Some(true),
        allow_missing_builtins: Some(false),
        ..Default::default()
    };

    //this entrypoint tells which function to run in the cairo program
    let program_content = std::fs::read(compiled_program_path)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
    let program = Program::from_bytes(&program_content, Some(cairo_run_config.entrypoint))
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

    // Prepare execution scopes to allow running pythonic hints for args_gen
    let mut exec_scopes = ExecutionScopes::new();
    let dict_manager = DictManager::new();
    exec_scopes.insert_value("dict_manager", Rc::new(RefCell::new(dict_manager)));

    // Initialize a python context object that will be accessible throughout the execution of
    // all hints.
    // This enables us to directly use the Python identifiers passed in, avoiding the need to
    // serialize and deserialize the program JSON.
    Python::with_gil(|py| {
        let context = PyDict::new(py);
        context.set_item("program_input", program_input)?;

        let identifiers = program
            .iter_identifiers()
            .map(|(name, identifier)| (name.to_string(), identifier.clone()))
            .collect::<HashMap<String, Identifier>>();

        // Insert the _rust_ program_identifiers in the exec_scopes, so that we're able to
        // pull identifier data when executing hints to build VmConsts.
        exec_scopes.insert_value("__program_identifiers__", identifiers);

        // Store empty python identifiers directly in the context
        context
            .set_item("py_identifiers", PyDict::new(py))
            .map_err(|e: PyErr| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        // We don't need `serialize` to be available in the context - inject a None value.
        context.set_item("cairo_file", Option::<String>::None)?;

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
        exec_scopes.insert_value("__context__", unbounded_context);
        Ok::<(), PyErr>(())
    })?;

    Ok((program, exec_scopes, cairo_run_config))
}

/// Generate trace and related artifacts from program input.
#[pyfunction]
pub fn generate_trace(
    entrypoint: String,
    program_input: PyObject,
    compiled_program_path: String,
    output_path: PathBuf,
) -> PyResult<()> {
    // Limit tracing to the current module
    let filter = EnvFilter::new("vm::vm::runner=info,warn");
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_span_events(FmtSpan::ENTER | FmtSpan::CLOSE)
        .with_env_filter(filter)
        .init();

    let (program, exec_scopes, cairo_run_config) =
        prepare_cairo_execution(&entrypoint, program_input, &compiled_program_path)?;

    let run_span = tracing::span!(tracing::Level::INFO, "cairo_run_program");
    let _run_span_guard = run_span.enter();
    let mut hint_processor = HintProcessor::default().with_dynamic_python_hints(false).build();
    let cairo_runner = match cairo_run::cairo_run_program_with_initial_scope(
        &program,
        &cairo_run_config,
        &mut hint_processor,
        exec_scopes,
    ) {
        Ok(runner) => runner,
        Err(error) => {
            tracing::error!("Failed to run program: {}", error);
            panic!("Failed to run block, exiting");
        }
    };
    drop(_run_span_guard);

    let execution_resources = cairo_runner.get_execution_resources().unwrap();
    tracing::info!("Execution resources: {:?}", execution_resources);

    // Write prover input infos
    let prover_input_info =
        cairo_runner.get_prover_input_info().expect("Unable to get prover input info");
    if let Some(parent) = output_path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(output_path, serde_json::to_string(&prover_input_info).map_err(to_pyerr)?)?;

    Ok(())
}

/// Run the full trace-generation, proving and verification pipeline
#[pyfunction]
pub fn run_end_to_end(
    entrypoint: String,
    program_input: PyObject,
    compiled_program_path: String,
    proof_path: PathBuf,
    verify: bool,
) -> PyResult<()> {
    // Limit tracing to the current module
    let filter = EnvFilter::new("vm::vm::runner=info,warn");
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_span_events(FmtSpan::ENTER | FmtSpan::CLOSE)
        .with_env_filter(filter)
        .init();

    let run_span = tracing::span!(tracing::Level::INFO, "cairo_run_program");
    let _run_span_guard = run_span.enter();
    let (program, exec_scopes, run_config) =
        prepare_cairo_execution(&entrypoint, program_input, &compiled_program_path)?;

    let mut hint_processor = HintProcessor::default().with_dynamic_python_hints(false).build();
    let cairo_runner = cairo_run::cairo_run_program_with_initial_scope(
        &program,
        &run_config,
        &mut hint_processor,
        exec_scopes,
    )
    .map_err(to_pyerr)?;
    drop(_run_span_guard);

    let cairo_input =
        stwo_cairo_adapter::plain::adapt_finished_runner(cairo_runner).map_err(to_pyerr)?;

    prove_with_stwo(cairo_input, Some(proof_path), verify).map_err(to_pyerr)
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
