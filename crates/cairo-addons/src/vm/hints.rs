use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::{
            builtin_hint_processor_definition::{BuiltinHintProcessor, HintFunc},
            memcpy_hint_utils::add_segment,
            sha256_utils::sha256_finalize,
        },
        hint_processor_definition::{HintProcessorLogic, HintReference},
    },
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{
        errors::hint_errors::HintError,
        runners::cairo_runner::{ResourceTracker, RunResources},
        vm_core::VirtualMachine,
    },
    Felt252,
};
use std::{collections::HashMap, fmt, rc::Rc};

use super::{
    hint_definitions::{
        BYTES_HINTS, CIRCUITS_HINTS, CURVE_HINTS, DICT_HINTS, ETHEREUM_HINTS, HASHDICT_HINTS,
        MATHS_HINTS, PRECOMPILES_HINTS, UTILS_HINTS,
    },
    hint_loader::load_python_hints,
};

#[cfg(feature = "pythonic-hints")]
use super::pythonic_hint::generic_python_hint;
#[cfg(feature = "pythonic-hints")]
use cairo_vm::hint_processor::builtin_hint_processor::builtin_hint_processor_definition::HintProcessorData;

/// A struct representing a hint.
pub struct Hint {
    /// The hint id, ie the raw string written in the Cairo code in between `%{` and `%}`.
    id: String,
    /// The hint function.
    pub func: Rc<HintFunc>,
}

impl Hint {
    pub fn new<F>(id: String, logic: F) -> Self
    where
        F: Fn(
                &mut VirtualMachine,
                &mut ExecutionScopes,
                &HashMap<String, HintReference>,
                &ApTracking,
                &HashMap<String, Felt252>,
            ) -> Result<(), HintError>
            + 'static
            + Sync,
    {
        Self { id, func: Rc::new(HintFunc(Box::new(logic))) }
    }
}

/// A wrapper around [`BuiltinHintProcessor`] to manage hint registration.
pub struct HintProcessor {
    inner: BuiltinHintProcessor,
    /// A map of hint IDs to their corresponding hint code.
    python_hints: HashMap<String, String>,
    /// A fallback function that will be used if the hint is not found
    /// and will interpret the hint code as Python code.
    #[cfg(feature = "pythonic-hints")]
    pythonic_hint_executor: Option<Rc<HintFunc>>,
    #[cfg(not(feature = "pythonic-hints"))]
    pythonic_hint_executor: Option<()>,
}

impl HintProcessor {
    pub fn new(run_resources: RunResources) -> Self {
        let python_hints = load_python_hints().unwrap_or_else(|_| {
            eprintln!("Warning: Failed to load Python hints, falling back to empty map");
            HashMap::new()
        });
        Self {
            inner: BuiltinHintProcessor::new(HashMap::new(), run_resources),
            python_hints,
            pythonic_hint_executor: None,
        }
    }

    /// A function where we initialize all hints, but we consider that the compiled code contains
    /// the hint id and not some python code.
    pub fn default_no_python_mapping() -> Self {
        let mut hints: Vec<fn() -> Hint> = vec![add_segment_hint, finalize_sha256_hint];
        hints.extend_from_slice(DICT_HINTS);
        hints.extend_from_slice(HASHDICT_HINTS);
        hints.extend_from_slice(UTILS_HINTS);
        hints.extend_from_slice(BYTES_HINTS);
        hints.extend_from_slice(MATHS_HINTS);
        hints.extend_from_slice(ETHEREUM_HINTS);
        hints.extend_from_slice(CURVE_HINTS);
        hints.extend_from_slice(CIRCUITS_HINTS);
        hints.extend_from_slice(PRECOMPILES_HINTS);
        Self::new(RunResources::default()).with_hints(hints, false)
    }

    /// Add hints to the hint processor
    ///
    /// If map_python_code is true, the hint code will be mapped to the expanded python code, not
    /// the id string.
    #[must_use]
    pub fn with_hints(mut self, hints: Vec<fn() -> Hint>, map_python_code: bool) -> Self {
        for fn_hint in hints {
            let hint = fn_hint();
            let hint_code = if map_python_code {
                self.python_hints.get(&hint.id).unwrap_or(&hint.id).to_string()
            } else {
                hint.id.clone()
            };
            self.inner.add_hint(hint_code, hint.func.clone());
        }
        self
    }

    #[must_use]
    pub fn with_run_resources(self, run_resources: RunResources) -> Self {
        Self {
            inner: BuiltinHintProcessor::new(self.inner.extra_hints, run_resources),
            python_hints: self.python_hints,
            pythonic_hint_executor: self.pythonic_hint_executor,
        }
    }

    /// Add support for dynamic Python hints
    #[cfg(feature = "pythonic-hints")]
    #[must_use]
    pub fn with_dynamic_python_hints(mut self) -> Self {
        // Store the generic Python hint executor for fallback
        self.pythonic_hint_executor = Some(generic_python_hint().func.clone());
        self
    }

    /// No-op version for when dynamic hints are disabled
    #[cfg(not(feature = "pythonic-hints"))]
    #[must_use]
    pub fn with_dynamic_python_hints(self) -> Self {
        self
    }

    /// Build the hint processor
    pub fn build(self) -> HintProcessor {
        HintProcessor {
            inner: self.inner,
            python_hints: self.python_hints,
            pythonic_hint_executor: self.pythonic_hint_executor,
        }
    }
}

impl HintProcessorLogic for HintProcessor {
    /// Executes a hint. If the hint is not found and dynamic hints are enabled, it will try to
    /// execute the hint as Python code. If dynamic hints are disabled, it will silently ignore
    /// unknown hints.
    fn execute_hint(
        &mut self,
        vm: &mut VirtualMachine,
        exec_scopes: &mut ExecutionScopes,
        hint_data: &Box<dyn std::any::Any>,
        constants: &HashMap<String, Felt252>,
    ) -> Result<(), HintError> {
        // Try to execute the hint with the inner processor
        let result = self.inner.execute_hint(vm, exec_scopes, hint_data, constants);

        match result {
            Ok(_) => Ok(()),
            #[cfg(feature = "pythonic-hints")]
            Err(HintError::UnknownHint(_hint_str)) => {
                // If the hint is unknown and we have a dynamic hint executor, try it
                if let Some(pythonic_hint_func) = &self.pythonic_hint_executor {
                    // Extract the hint code from the hint_data
                    let hint_data = match hint_data.downcast_ref::<HintProcessorData>() {
                        Some(data) => data,
                        None => {
                            return Err(HintError::CustomHint(Box::from(
                                "Failed to downcast hint_data to HintProcessorData".to_string(),
                            )))
                        }
                    };
                    let hint_code = hint_data.code.clone();
                    //TODO: This is a hack to avoid executing the hint if it contains the word
                    // "logger" for block proving. We need to find a way to skip
                    // all logging hints when running in "production"
                    if hint_code.contains("logger") {
                        return Ok(())
                    }
                    exec_scopes.assign_or_update_variable("__hint_code__", Box::new(hint_code));

                    // Execute the dynamic hint
                    let pythonic_hint_func = pythonic_hint_func.0.as_ref();
                    let dynamic_result = pythonic_hint_func(
                        vm,
                        exec_scopes,
                        &hint_data.ids_data,
                        &hint_data.ap_tracking,
                        constants,
                    );

                    dynamic_result.map_err(|e| {
                        // Wrap the error with context about which hint failed
                        HintError::CustomHint(Box::from(format!(
                            "Dynamic hint execution failed for hint: '{}'. Error: {}",
                            hint_data.code, e
                        )))
                    })
                } else {
                    // If dynamic hints are disabled, silently ignore unknown hints
                    Ok(())
                }
            }
            #[cfg(not(feature = "pythonic-hints"))]
            Err(HintError::UnknownHint(hint_str)) => {
                // When dynamic hints are disabled, just return the original error
                Err(HintError::UnknownHint(hint_str))
            }
            Err(err) => Err(err),
        }
    }
}

impl ResourceTracker for HintProcessor {
    fn consumed(&self) -> bool {
        self.inner.consumed()
    }
    fn get_n_steps(&self) -> Option<usize> {
        self.inner.get_n_steps()
    }
    fn consume_step(&mut self) {
        self.inner.consume_step()
    }
    fn run_resources(&self) -> &RunResources {
        self.inner.run_resources()
    }
}

impl Default for HintProcessor {
    fn default() -> Self {
        let mut hints: Vec<fn() -> Hint> = vec![add_segment_hint, finalize_sha256_hint];
        hints.extend_from_slice(DICT_HINTS);
        hints.extend_from_slice(HASHDICT_HINTS);
        hints.extend_from_slice(UTILS_HINTS);
        hints.extend_from_slice(BYTES_HINTS);
        hints.extend_from_slice(MATHS_HINTS);
        hints.extend_from_slice(ETHEREUM_HINTS);
        hints.extend_from_slice(CURVE_HINTS);
        hints.extend_from_slice(CIRCUITS_HINTS);
        hints.extend_from_slice(PRECOMPILES_HINTS);
        Self::new(RunResources::default()).with_hints(hints, true)
    }
}

impl fmt::Debug for HintProcessor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("HintProcessor")
            .field("extra_hints", &self.inner.extra_hints.keys())
            .field("run_resources", &"...")
            .finish()
    }
}

pub fn add_segment_hint() -> Hint {
    Hint::new(
        String::from("memory[ap] = to_felt_or_relocatable(segments.add())"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> { add_segment(vm) },
    )
}

// A patch of the LambdaClass CairoVM Rust hint, because the one in cairo-lang 0.13a is _slightly_
// different.
pub const SHA256_FINALIZE: &str = r#"# Add dummy pairs of input and output.
from starkware.cairo.common.cairo_sha256.sha256_utils import (
    IV,
    compute_message_schedule,
    sha2_compress_function,
)

number_of_missing_blocks = (-ids.n) % ids.BATCH_SIZE
assert 0 <= number_of_missing_blocks < 20
_sha256_input_chunk_size_felts = ids.SHA256_INPUT_CHUNK_SIZE_FELTS
assert 0 <= _sha256_input_chunk_size_felts < 100

message = [0] * _sha256_input_chunk_size_felts
w = compute_message_schedule(message)
output = sha2_compress_function(IV, w)
padding = (message + IV + output) * number_of_missing_blocks
segments.write_arg(ids.sha256_ptr_end, padding)"#;

pub fn finalize_sha256_hint() -> Hint {
    Hint::new(
        String::from(SHA256_FINALIZE),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         ids_data: &HashMap<String, HintReference>,
         ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> Result<(), HintError> { sha256_finalize(vm, ids_data, ap_tracking) },
    )
}
