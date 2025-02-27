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
//! ## Limitations
//!
//! - Direct mutation of `ids` variables is not supported.
//! - Direct mutation of `memory` is not supported.
//! - Access to `segments` is not implemented.
//! - Performance is slower than native Rust hints, but suitable for debugging

use cairo_vm::{
    hint_processor::hint_processor_definition::HintReference,
    serde::deserialize_program::{ApTracking, Identifier},
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use pyo3::{prelude::*, types::PyDict};
use std::{collections::HashMap, ffi::CString, path::PathBuf};
use thiserror::Error;

use super::{
    dict_manager::PyDictManager,
    hints::Hint,
    memory_segments::{PyMemorySegmentManager, PyMemoryWrapper},
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
pub struct DynamicPythonHintExecutor {
    /// Whether the Python interpreter has been initialized
    initialized: bool,
    /// Optional Python path to add during initialization
    python_path: Option<PathBuf>,
}

impl Default for DynamicPythonHintExecutor {
    fn default() -> Self {
        Self::new()
    }
}

impl DynamicPythonHintExecutor {
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
    ) -> Result<(), HintError> {
        // Ensure Python interpreter is initialized
        self.ensure_initialized().map_err(|e| DynamicHintError::PythonInit(e.to_string()))?;

        Python::with_gil(|py| {
            // Create a Python dict for the locals
            let locals = PyDict::new(py);
            let globals = PyDict::new(py);

            // Create a memory wrapper using the existing PyMemoryWrapper
            let memory_wrapper = PyMemoryWrapper { vm };
            let memory = Py::new(py, memory_wrapper)
                .map_err(|e| DynamicHintError::PyObjectCreation(e.to_string()))?;
            // Add the memory wrapper to locals
            locals
                .set_item("memory", &memory)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            // Create a segments wrapper using the existing PySegmentsWrapper
            let segments_wrapper = PyMemorySegmentManager { vm };
            let segments = Py::new(py, segments_wrapper)
                .map_err(|e| DynamicHintError::PyObjectCreation(e.to_string()))?;
            // Add the segments wrapper to locals
            locals
                .set_item("segments", &segments)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;
            globals
                .set_item("segments", &segments)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            // Create a dict manager wrapper using the existing PyDictManagerWrapper
            let dict_manager = exec_scopes
                .get_dict_manager()
                .map_err(|e| DynamicHintError::PyObjectCreation(e.to_string()))?;
            let py_dict_manager = PyDictManager { inner: dict_manager };
            let py_dict_manager_wrapper = Py::new(py, py_dict_manager)
                .map_err(|e| DynamicHintError::PyObjectCreation(e.to_string()))?;
            // Add the dict manager wrapper to locals
            locals
                .set_item("dict_manager", &py_dict_manager_wrapper)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            globals
                .set_item("dict_manager", &py_dict_manager_wrapper)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            // Get the program identifiers that we inserted into the execution scope upon runner
            // initialization
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

            // Create VmConstsDict using the new implementation
            let py_ids_dict =
                create_vm_consts_dict(vm, &program_identifiers, ids_data, ap_tracking, py)
                    .map_err(|e| DynamicHintError::PyObjectCreation(e.to_string()))?;

            // Add the ids dictionary to locals
            locals
                .set_item("ids", py_ids_dict)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            // Get the program JSON if it exists
            let full_hint_code =
                if let Ok(program_json) = exec_scopes.get_ref::<Vec<u8>>("__program_json__") {
                    // Add the program_json to locals as a string
                    locals
                        .set_item("__program_json__", program_json)
                        .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

                    globals
                        .set_item("__program_json__", program_json)
                        .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

                    // Import needed modules for Program deserialization
                    let injected_py_code = r#"
import json
import sys
import io
from starkware.cairo.lang.compiler.program import Program
from pathlib import Path

# Try to import Serde, with fallback to empty class if not available
try:
    from cairo_addons.testing.serde import Serde
except ImportError:
    class Serde:
        def __init__(self, *args, **kwargs):
            raise ImportError("cairo_addons.testing.serde not found")


def get_serde():
    """
    Create a Serde instance with the program identifiers from the deserialized program.

    Args:
        segments: A segments manager instance (required)
        dict_manager: A dict manager instance (required)
        cairo_file: Optional path to the Cairo file

    Returns:
        A Serde instance initialized with the program identifiers
    """
    if segments is None or dict_manager is None:
        raise ValueError("Both segments and dict_manager must be available in the execution scope")

    from starkware.cairo.lang.compiler.program import Program
    from tests.utils.serde import Serde
    program = Program.Schema().loads(__program_json__)

    return Serde(
        segments=segments,
        program_identifiers=program.identifiers,
        dict_manager=dict_manager,
    )

def serialize(variable):
    from starkware.cairo.lang.compiler.program import Program
    from tests.utils.serde import Serde
    program = Program.Schema().loads(__program_json__)

    serde = Serde(
        segments=segments,
        program_identifiers=program.identifiers,
        dict_manager=dict_manager,
    )

    if type

"#;

                    format!("{}\n{}", injected_py_code, hint_code)
                } else {
                    hint_code.to_string()
                };

            // Execute the Python code
            let hint_code_c_string = CString::new(full_hint_code)
                .map_err(|e| DynamicHintError::CStringConversion(e.to_string()))?;
            py.run(&hint_code_c_string, Some(&globals), Some(&locals))
                .map_err(|e| DynamicHintError::PythonExecution(e.to_string()))?;

            Ok(())
        })
    }
}

/// A generic hint that can execute arbitrary Python code
pub fn generic_python_hint() -> Hint {
    // Create a static executor that will be reused
    static EXECUTOR: std::sync::OnceLock<std::sync::Mutex<DynamicPythonHintExecutor>> =
        std::sync::OnceLock::new();
    let executor = EXECUTOR.get_or_init(|| std::sync::Mutex::new(DynamicPythonHintExecutor::new()));

    Hint::new(
        String::from("__dynamic_python_hint__"),
        move |vm: &mut VirtualMachine,
              exec_scopes: &mut ExecutionScopes,
              ids_data: &HashMap<String, HintReference>,
              ap_tracking: &ApTracking,
              _constants: &HashMap<String, Felt252>|
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

            // Lock the executor to get mutable access
            let mut locked_executor = executor.lock().map_err(|e| {
                HintError::CustomHint(Box::from(format!("Failed to lock executor: {}", e)))
            })?;

            // Execute the Python code
            locked_executor.execute_hint(&hint_code, vm, exec_scopes, ids_data, ap_tracking)
        },
    )
}
