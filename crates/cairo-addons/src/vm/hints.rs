use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::{
            builtin_hint_processor_definition::{BuiltinHintProcessor, HintFunc},
            memcpy_hint_utils::add_segment,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{
        errors::hint_errors::HintError, runners::cairo_runner::RunResources,
        vm_core::VirtualMachine,
    },
    Felt252,
};
use std::{collections::HashMap, fmt, rc::Rc};

use super::{
    hint_definitions::{DICT_HINTS, HASHDICT_HINTS, UTILS_HINTS},
    hint_loader::load_python_hints,
};

/// A struct representing a hint.
pub struct Hint {
    /// The hint id, ie the raw string written in the Cairo code in between `%{` and `%}`.
    id: String,
    /// The hint function.
    func: Rc<HintFunc>,
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
    python_hints: HashMap<String, String>,
}

impl HintProcessor {
    pub fn new(run_resources: RunResources) -> Self {
        let python_hints = load_python_hints().unwrap();
        Self { inner: BuiltinHintProcessor::new(HashMap::new(), run_resources), python_hints }
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
        }
    }

    pub fn build(self) -> BuiltinHintProcessor {
        self.inner
    }
}

impl Default for HintProcessor {
    fn default() -> Self {
        let mut hints: Vec<fn() -> Hint> = vec![add_segment_hint];
        hints.extend_from_slice(DICT_HINTS);
        hints.extend_from_slice(HASHDICT_HINTS);
        hints.extend_from_slice(UTILS_HINTS);

        Self::new(RunResources::default()).with_hints(hints)
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
