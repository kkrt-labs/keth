//! # Dynamic Python Hint Execution System for Cairo VM
//!
//! This module provides a dynamic Python hint execution system for Cairo VM that allows
//! arbitrary Python code to be executed within Cairo hints. It bridges Rust memory and
//! Cairo variables to Python, enabling a more flexible hint system without
//! requiring pre-registration of all possible hints.
//!
//! ## Implemented Features
//!
//! - Access to the `memory` object
//! - Access to the `ids` object
//! - Access to Cairo variables with full type information (e.g. struct members, pointer
//!   dereferencing) through the `ids` object
//!
//! ## Usage in Hint Processor
//!
//! The dynamic hint executor is integrated with the hint processor as a fallback mechanism.
//! When a hint is not found in the pre-registered hint registry, the system attempts to
//! execute it as Python code using the dynamic executor.
//!
//! ## Example
//!
//! In a Cairo program:
//!
//! ```cairo
//! %{
//!     # This Python code will be executed dynamically
//!     print(f"Value of x: {ids.x}")
//!     print(f"Address of x: {ids.x.address_}")
//!
//!     # Access struct members
//!     if hasattr(ids, 'my_struct'):
//!         print(f"Struct member: {ids.my_struct.member}")
//!
//!     # Use breakpoint for debugging
//!     # breakpoint()
//! %}
//! ```
//!
//! Serialize a variable from `ids` using the `serialize` function.
//! This uses the factory function `serialize` that is injected into the execution scope in
//! runner.rs.
//!
//! ```cairo
//! tempvar evm = Evm(...)
//! %{ serialize(ids.evm) %}
//! ```
//!
//! ## Limitations
//!
//! - Direct mutation of `ids` variables is not supported.
//! - Direct mutation of `memory` is not supported.
//! - Access to `segments` is not implemented.
//! - Performance is slower than native Rust hints, but suitable for debugging

use cairo_vm::{
    hint_processor::hint_processor_definition::HintReference,
    serde::deserialize_program::{ApTracking, Identifier},
    types::{builtin_name::BuiltinName, exec_scope::ExecutionScopes},
    vm::{
        errors::hint_errors::HintError, runners::builtin_runner::BuiltinRunner,
        vm_core::VirtualMachine,
    },
    Felt252,
};
use pyo3::{prelude::*, types::PyDict};
use std::{collections::HashMap, ffi::CString, path::PathBuf};
use thiserror::Error;

use super::{
    dict_manager::PyDictManager,
    hints::Hint,
    memory_segments::{PyMemorySegmentManager, PyMemoryWrapper},
    mod_builtin_runner::PyModBuiltinRunner,
    relocatable::PyRelocatable,
    vm_consts::create_vm_consts_dict,
};

/// Error type for dynamic Python hint operations
///
/// This provides better error context and simplifies error handling throughout the code.
#[derive(Error, Debug)]
pub enum DynamicHintError {
    #[error("Python initialization error: {0}")]
    PythonInit(String),

    #[error("Failed to create Python object: {0}")]
    PyObjectCreation(String),

    #[error("Failed to set Python dictionary item: {0}")]
    PyDictSet(String),

    #[error("Failed to get value from variable: {0}")]
    VariableAccess(String),

    #[error("Invalid variable reference: {0}")]
    InvalidReference(String),

    #[error("Python execution error: {0}")]
    PythonExecution(String),

    #[error("Failed to convert hint code to CString: {0}")]
    CStringConversion(String),

    #[error("Unknown variable type: {0}")]
    UnknownVariableType(String),

    #[error("Memory error: {0}")]
    MemoryError(String),
}

impl From<DynamicHintError> for HintError {
    fn from(err: DynamicHintError) -> Self {
        HintError::CustomHint(Box::from(err.to_string()))
    }
}

impl From<PyErr> for DynamicHintError {
    fn from(err: PyErr) -> Self {
        DynamicHintError::PyObjectCreation(err.to_string())
    }
}

/// A Python hint executor that executes dynamic Python hints with access to Cairo VM memory
///
/// This executor allows running Python code with access to Cairo VM memory and variables.
/// It provides the `memory` object for accessing VM memory and the `ids` dictionary
/// for accessing variables defined in the Cairo program.
pub struct PythonicHintExecutor {
    /// Whether the Python interpreter has been initialized
    initialized: bool,
    /// Optional Python path to add during initialization
    python_path: Option<PathBuf>,
}

impl Default for PythonicHintExecutor {
    fn default() -> Self {
        Self::new()
    }
}

impl PythonicHintExecutor {
    /// Create a new dynamic Python hint executor
    pub fn new() -> Self {
        Self { initialized: false, python_path: None }
    }

    /// Initialize the Python interpreter if not already initialized
    fn ensure_initialized(&mut self) -> PyResult<()> {
        if self.initialized {
            return Ok(());
        }

        Python::with_gil(|py| {
            // Import the sys module to add paths to sys.path
            let sys = PyModule::import(py, "sys")?;
            let path = sys.getattr("path")?;

            // Add current directory
            path.call_method1("append", (".",))?;

            // Add custom path if specified
            if let Some(ref custom_path) = self.python_path {
                path.call_method1("append", (custom_path,))?;
            }

            PyResult::Ok(())
        })?;

        self.initialized = true;
        Ok(())
    }

    /// Execute a Python hint with access to VM state
    pub fn execute_hint(
        &mut self,
        hint_code: &str,
        vm: &mut VirtualMachine,
        exec_scopes: &mut ExecutionScopes,
        ids_data: &HashMap<String, HintReference>,
        ap_tracking: &ApTracking,
        constants: &HashMap<String, Felt252>,
        hint_accessible_scopes: &Vec<String>,
    ) -> Result<(), HintError> {
        self.ensure_initialized().map_err(|e| DynamicHintError::PythonInit(e.to_string()))?;

        Python::with_gil(|py| {
            // Load the context object - see runner.rs for more details
            let context: &Py<PyDict> = exec_scopes
                .get_ref::<Py<PyDict>>("__context__")
                .map_err(|e| DynamicHintError::PyObjectCreation(e.to_string()))?;
            let bounded_context = context.bind(py);

            // Add the memory wrapper to context
            let memory_wrapper = PyMemoryWrapper { inner: &mut vm.segments.memory };
            let memory = Py::new(py, memory_wrapper)
                .map_err(|e| DynamicHintError::PyObjectCreation(e.to_string()))?;
            bounded_context
                .set_item("memory", &memory)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            // Add the segments wrapper to context
            let segments_wrapper = PyMemorySegmentManager { inner: &mut vm.segments };
            let segments = Py::new(py, segments_wrapper)
                .map_err(|e| DynamicHintError::PyObjectCreation(e.to_string()))?;
            bounded_context
                .set_item("segments", &segments)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            // Add the dict manager wrapper to context
            let dict_manager = exec_scopes
                .get_dict_manager()
                .map_err(|e| DynamicHintError::PyObjectCreation(e.to_string()))?;
            let py_dict_manager = PyDictManager { inner: dict_manager };
            let py_dict_manager_wrapper = Py::new(py, py_dict_manager)
                .map_err(|e| DynamicHintError::PyObjectCreation(e.to_string()))?;
            bounded_context
                .set_item("dict_manager", &py_dict_manager_wrapper)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            // Add the mod builtin runner wrapper to context. Expose it through a builtin_runners
            // dict in the keys "add_mod_builtin" and "mul_mod_builtin"
            let add_mod_builtin = vm.builtin_runners.iter().find_map(|b| match b {
                BuiltinRunner::Mod(b) if b.name() == BuiltinName::add_mod => Some(b),
                _ => None,
            });
            let mul_mod_builtin = vm.builtin_runners.iter().find_map(|b| match b {
                BuiltinRunner::Mod(b) if b.name() == BuiltinName::mul_mod => Some(b),
                _ => None,
            });

            let builtin_runners = PyDict::new(py);
            if let Some(add_mod) = add_mod_builtin {
                let add_mod_builtin_runner_wrapper = PyModBuiltinRunner { inner: add_mod.clone() };
                builtin_runners
                    .set_item("add_mod_builtin", add_mod_builtin_runner_wrapper)
                    .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;
            }

            if let Some(mul_mod) = mul_mod_builtin {
                let mul_mod_builtin_runner_wrapper = PyModBuiltinRunner { inner: mul_mod.clone() };
                builtin_runners
                    .set_item("mul_mod_builtin", mul_mod_builtin_runner_wrapper)
                    .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;
            }

            bounded_context
                .set_item("builtin_runners", &builtin_runners)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            // Make ap, pc, fp accessible from the hint
            let ap: PyRelocatable = vm.get_ap().into();
            let pc: PyRelocatable = vm.get_pc().into();
            let fp: PyRelocatable = vm.get_fp().into();
            bounded_context
                .set_item("ap", ap)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;
            bounded_context
                .set_item("pc", pc)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;
            bounded_context
                .set_item("fp", fp)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            // Get the _rust_ program identifiers that we inserted into the execution scope upon
            // runner initialization to initialize VmConsts, and add them to the context
            let program_identifiers = match exec_scopes
                .get_ref::<HashMap<String, Identifier>>("__program_identifiers__")
            {
                Ok(identifiers) => identifiers.clone(),
                Err(e) => {
                    return Err(HintError::CustomHint(Box::from(format!(
                        "No program identifiers found in execution scope: {:?}",
                        e
                    ))))
                }
            };
            let py_ids_dict = create_vm_consts_dict(
                vm,
                &program_identifiers,
                ids_data,
                ap_tracking,
                constants,
                hint_accessible_scopes,
                py,
            )
            .map_err(|e| DynamicHintError::PyObjectCreation(e.to_string()))?;
            bounded_context
                .set_item("ids", py_ids_dict)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            // Explicit imports of the python `ModBuiltinRunner` class in a hint should be replaced
            // by our binding.
            let full_hint_code = PythonCodeInjector::new(hint_code)
                .with_base_imports()
                .with_serialize()
                .with_gen_arg()
                .replace_hint_code_chunk(
                    "from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner",
                    "from cairo_addons.vm import ModBuiltinRunner",
                )
                .build();

            let hint_code_c_string = CString::new(full_hint_code)
                .map_err(|e| DynamicHintError::CStringConversion(e.to_string()))?;

            // Run the hint code
            py.run(&hint_code_c_string, Some(bounded_context), None).map_err(|e| {
                let traceback = e.traceback(py).unwrap();
                let error_message = e.to_string();
                DynamicHintError::PythonExecution(format!(
                    "{}\nTraceback:\n{}",
                    error_message,
                    traceback.format().unwrap()
                ))
            })?;

            Ok(())
        })
    }
}

/// A generic hint that can execute arbitrary Python code
pub fn generic_python_hint() -> Hint {
    // Create a static executor that will be reused
    static EXECUTOR: std::sync::OnceLock<std::sync::Mutex<PythonicHintExecutor>> =
        std::sync::OnceLock::new();
    let executor = EXECUTOR.get_or_init(|| std::sync::Mutex::new(PythonicHintExecutor::new()));

    Hint::new(
        String::from("__dynamic_python_hint__"),
        move |vm: &mut VirtualMachine,
              exec_scopes: &mut ExecutionScopes,
              ids_data: &HashMap<String, HintReference>,
              ap_tracking: &ApTracking,
              constants: &HashMap<String, Felt252>|
              -> Result<(), HintError> {
            // This must match the type of the hint code inserted in the execution scope
            let hint_code = match exec_scopes.get_ref::<String>("__hint_code__") {
                Ok(code) => code.clone(),
                Err(e) => {
                    return Err(HintError::CustomHint(Box::from(format!(
                        "No hint code found in execution scope: {:?}",
                        e
                    ))))
                }
            };

            //TODO: PR lambdaclass an make it an `execute_hint` argument?
            let hint_accessible_scopes =
                match exec_scopes.get_ref::<Vec<String>>("__hint_accessible_scopes__") {
                    Ok(scopes) => scopes.clone(),
                    Err(e) => {
                        return Err(HintError::CustomHint(Box::from(format!(
                            "No hint accessible scopes found in execution scope: {:?}",
                            e
                        ))))
                    }
                };

            // Lock the executor to get mutable access
            let mut locked_executor = executor.lock().map_err(|e| {
                HintError::CustomHint(Box::from(format!("Failed to lock executor: {}", e)))
            })?;

            // Execute the Python code
            locked_executor.execute_hint(
                &hint_code,
                vm,
                exec_scopes,
                ids_data,
                ap_tracking,
                constants,
                &hint_accessible_scopes,
            )
        },
    )
}

/// Builder for constructing Python injection code
struct PythonCodeInjector {
    code_parts: Vec<String>,
    hint_code: String,
}

impl PythonCodeInjector {
    /// Create a new injector instance from a hint code
    fn new(hint_code: &str) -> Self {
        Self { code_parts: Vec::new(), hint_code: hint_code.to_string() }
    }

    /// Add the base imports required for all injections
    fn with_base_imports(mut self) -> Self {
        self.code_parts.push("from functools import partial".to_string());
        self.code_parts
            .push("from starkware.cairo.lang.vm.relocatable import RelocatableValue".to_string());
        self.code_parts
            .push("to_felt_or_relocatable = RelocatableValue.to_felt_or_relocatable".to_string());
        self
    }

    /// Add serialization code
    fn with_serialize(mut self) -> Self {
        self.code_parts.push(r#"
    serialize = partial(serialize, segments=segments, program_identifiers=py_identifiers, dict_manager=dict_manager, cairo_file=cairo_file)
"#.trim().to_string());
        self
    }

    /// Add gen_arg partial function (always included)
    fn with_gen_arg(mut self) -> Self {
        self.code_parts.push("gen_arg = partial(_gen_arg, dict_manager, segments)".to_string());
        self
    }

    /// Replace a substring of the hint code by another substring
    fn replace_hint_code_chunk(mut self, search: &str, replace: &str) -> Self {
        self.hint_code = self.hint_code.replace(search, replace);
        self
    }

    /// Build the final injected code string
    fn build(self) -> String {
        let hint_lines: Vec<&str> = self.hint_code.lines().collect();
        let mut all_parts = self.code_parts;
        all_parts.extend(hint_lines.iter().map(|s| s.to_string()));
        all_parts.join("\n")
    }
}
