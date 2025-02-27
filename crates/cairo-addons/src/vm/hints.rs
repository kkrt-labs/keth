use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::{
            builtin_hint_processor_definition::{
                BuiltinHintProcessor, HintFunc, HintProcessorData,
            },
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
    dynamic_hint::generic_python_hint,
    hint_definitions::{
        BYTES_HINTS, CIRCUITS_HINTS, CURVE_HINTS, DICT_HINTS, ETHEREUM_HINTS, HASHDICT_HINTS,
        MATHS_HINTS, PRECOMPILES_HINTS, UTILS_HINTS,
    },
    hint_loader::load_python_hints,
};

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
    dynamic_hint_executor: Option<Rc<HintFunc>>,
}

impl HintProcessor {
    pub fn new(run_resources: RunResources) -> Self {
        let python_hints = load_python_hints().unwrap();
        Self {
            inner: BuiltinHintProcessor::new(HashMap::new(), run_resources),
            python_hints,
            dynamic_hint_executor: None,
        }
    }

    #[must_use]
    pub fn with_hints(mut self, hints: Vec<fn() -> Hint>) -> Self {
        for fn_hint in hints {
            let hint = fn_hint();
            self.inner.add_hint(
                self.python_hints.get(&hint.id).unwrap_or(&hint.id).to_string(),
                hint.func.clone(),
            );
        }
        self
    }

    #[must_use]
    pub fn with_run_resources(self, run_resources: RunResources) -> Self {
        Self {
            inner: BuiltinHintProcessor::new(self.inner.extra_hints, run_resources),
            python_hints: self.python_hints,
            dynamic_hint_executor: self.dynamic_hint_executor,
        }
    }

    /// Add support for dynamic Python hints
    #[must_use]
    pub fn with_dynamic_python_hints(mut self) -> Self {
        // Store the generic Python hint executor for fallback
        self.dynamic_hint_executor = Some(generic_python_hint().func.clone());
        self
    }

    /// Build the hint processor
    pub fn build(self) -> HintProcessor {
        HintProcessor {
            inner: self.inner,
            python_hints: self.python_hints,
            dynamic_hint_executor: self.dynamic_hint_executor,
        }
    }
}

impl HintProcessorLogic for HintProcessor {
    /// Executes a hint. If the hint is not found, it will try to execute the hint as Python code
    /// using the dynamic hint executor.
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
            Err(HintError::UnknownHint(_)) => {
                // If the hint is unknown, try the dynamic hint executor
                if let Some(dynamic_hint_func) = &self.dynamic_hint_executor {
                    // Extract the hint code from the hint_data
                    let hint_data = hint_data.downcast_ref::<HintProcessorData>().unwrap();
                    let hint_code = hint_data.code.clone();
                    exec_scopes.assign_or_update_variable("__hint_code__", Box::new(hint_code));

                    // Execute the dynamic hint
                    let dynamic_hint_func = dynamic_hint_func.0.as_ref();
                    let dynamic_result = dynamic_hint_func(
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
                    // If no dynamic hint executor is available, return the original error
                    let hint_data = hint_data.downcast_ref::<HintProcessorData>().unwrap();
                    Err(HintError::UnknownHint(hint_data.code.clone().into_boxed_str()))
                }
            }
            Err(err) => Err(err),
        }
    }
}

impl ResourceTracker for HintProcessor {
    fn consumed(&self) -> bool {
        self.inner.consumed()
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
        Self::new(RunResources::default()).with_hints(hints).with_dynamic_python_hints()
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
