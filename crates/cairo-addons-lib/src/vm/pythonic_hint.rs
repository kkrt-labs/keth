use cairo_vm::{
    hint_processor::hint_processor_definition::HintReference,
    serde::deserialize_program::{ApTracking},
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use pyo3::{prelude::*, types::PyDict};
use std::{collections::HashMap, ffi::CString, path::PathBuf};
use thiserror::Error;

use super::hints::Hint;

/// Error type for dynamic Python hint operations
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
        _vm: &mut VirtualMachine,
        _exec_scopes: &mut ExecutionScopes,
        _ids_data: &HashMap<String, HintReference>,
        _ap_tracking: &ApTracking,
        _constants: &HashMap<String, Felt252>,
    ) -> Result<(), DynamicHintError> {
        self.ensure_initialized().map_err(|e| DynamicHintError::PythonInit(e.to_string()))?;

        Python::with_gil(|py| {
            // Create a new dictionary for the execution context
            let bounded_context = PyDict::new(py);

            // Create a dictionary for the ids
            let py_ids_dict = PyDict::new(py);

            // Add ids to the context
            bounded_context
                .set_item("ids", py_ids_dict)
                .map_err(|e| DynamicHintError::PyDictSet(e.to_string()))?;

            let injected_py_code = PythonCodeInjector::new()
                .with_base_imports()
                .with_serialize()
                .with_gen_arg()
                .build();
            let full_hint_code = format!("{}\n{}", injected_py_code, hint_code);
            let hint_code_c_string = CString::new(full_hint_code)
                .map_err(|e| DynamicHintError::CStringConversion(e.to_string()))?;

            // Run the hint code
            py.run(&hint_code_c_string, Some(&bounded_context), None)
                .map_err(|e| DynamicHintError::PythonExecution(e.to_string()))?;

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
            locked_executor
                .execute_hint(
                    &hint_code,
                    vm,
                    exec_scopes,
                    ids_data,
                    ap_tracking,
                    constants,
                )
                .map_err(|e| HintError::CustomHint(Box::from(e.to_string())))
        },
    )
}

/// Helper struct to build Python code to inject into the hint execution context
pub struct PythonCodeInjector {
    code_parts: Vec<String>,
}

impl PythonCodeInjector {
    pub fn new() -> Self {
        Self { code_parts: Vec::new() }
    }

    pub fn with_base_imports(mut self) -> Self {
        self.code_parts.push(
            r#"
import sys
import json
from typing import Any, Dict, List, Optional, Union
"#
            .to_string(),
        );
        self
    }

    pub fn with_serialize(mut self) -> Self {
        self.code_parts.push(
            r#"
def serialize(obj: Any) -> None:
    """Serialize a Python object to JSON and store it in the execution scope."""
    try:
        json_str = json.dumps(obj)
        globals()['__serialized_data__'] = json_str
    except Exception as e:
        print(f"Error serializing object: {e}")
"#
            .to_string(),
        );
        self
    }

    pub fn with_gen_arg(mut self) -> Self {
        self.code_parts.push(
            r#"
def gen_arg() -> None:
    """Generate an argument for a function call."""
    pass
"#
            .to_string(),
        );
        self
    }

    pub fn build(self) -> String {
        self.code_parts.join("\n")
    }
} 