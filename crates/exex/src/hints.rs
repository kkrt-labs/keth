use crate::model::{block::KethBlock, payload::KethPayload};
use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::{
            builtin_hint_processor_definition::{BuiltinHintProcessor, HintFunc},
            hint_utils::insert_value_from_var_name,
            memcpy_hint_utils::add_segment,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::exec_scope::ExecutionScopes,
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use reth_primitives::SealedBlock;
use std::{collections::HashMap, fmt, rc::Rc};

/// The type of a hint execution result.
pub type HintExecutionResult = Result<(), HintError>;

/// A wrapper around [`BuiltinHintProcessor`] to manage hint registration.
pub struct KakarotHintProcessor {
    /// The underlying [`BuiltinHintProcessor`].
    processor: BuiltinHintProcessor,
}

/// Implementation of `Debug` for `KakarotHintProcessor`.
impl fmt::Debug for KakarotHintProcessor {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KakarotHintProcessor")
            .field("extra_hints", &self.processor.extra_hints.keys())
            .field("run_resources", &"...")
            .finish()
    }
}

impl Default for KakarotHintProcessor {
    fn default() -> Self {
        Self::new_empty()
            .with_hint(&add_segment_hint())
            .with_hint(&dict_manager_hint())
            .with_hint(&account_hint())
            .with_hint(&state_hint())
            .with_hint(&chain_id_hint())
            .with_hint(&dict_copy_hint())
            .with_hint(&dict_squash_hint())
            .with_hint(&block_hashes_hint())
    }
}

impl KakarotHintProcessor {
    /// Creates a new, empty [`KakarotHintProcessor`].
    pub fn new_empty() -> Self {
        Self { processor: BuiltinHintProcessor::new_empty() }
    }

    /// Adds a hint to the [`KakarotHintProcessor`].
    ///
    /// This method allows you to register a hint by providing a [`Hint`] instance.
    #[must_use]
    pub fn with_hint(mut self, hint: &Hint) -> Self {
        self.processor.add_hint(hint.name.clone(), hint.func.clone());
        self
    }

    /// Adds the block hint to the [`KakarotHintProcessor`].
    ///
    /// This method wraps the [`block_hint`] function, which creates a hint that is related to the
    /// given [`SealedBlock`]. The hint is then registered with the [`KakarotHintProcessor`].
    #[must_use]
    pub fn with_block(self, block: SealedBlock) -> Self {
        self.with_hint(&block_hint(block))
    }

    /// Returns the underlying [`BuiltinHintProcessor`].
    ///
    /// This allows the processor to be used elsewhere.
    pub fn build(self) -> BuiltinHintProcessor {
        self.processor
    }
}

/// A generic structure to encapsulate a hint with a closure that contains the specific logic.
pub struct Hint {
    /// The name of the hint.
    name: String,
    /// The function containing the hint logic.
    func: Rc<HintFunc>,
}

impl fmt::Debug for Hint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Hint").field("name", &self.name).field("func", &"...").finish()
    }
}

impl Hint {
    /// Creates a new [`Hint`] with the specified name and function logic.
    ///
    /// The logic is passed as a closure, which will be executed when the hint is triggered.
    pub fn new<F>(name: String, logic: F) -> Self
    where
        F: Fn(
                &mut VirtualMachine,
                &mut ExecutionScopes,
                &HashMap<String, HintReference>,
                &ApTracking,
                &HashMap<String, Felt252>,
            ) -> HintExecutionResult
            + 'static
            + Sync,
    {
        Self { name, func: Rc::new(HintFunc(Box::new(logic))) }
    }
}

/// Generates a hint to add a new memory segment.
///
/// This function adds a hint to the `HintProcessor` that creates a new memory segment in the
/// virtual machine. It maps the current memory pointer (`ap`) to the newly added segment.
pub fn add_segment_hint() -> Hint {
    Hint::new(
        String::from("memory[ap] = to_felt_or_relocatable(segments.add())"),
        |vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> HintExecutionResult {
            // Calls the function to add a new memory segment to the VM.
            add_segment(vm)
        },
    )
}

/// Proper header documentation needs to be defined after the implementation of the hint.
pub fn block_hint(block: SealedBlock) -> Hint {
    // Convert the SealedBlock into a KethBlock
    let keth_block: KethBlock = block.into();

    // Convert the KethBlock into a KethPayload
    let keth_payload: KethPayload = keth_block.into();

    Hint::new(
        String::from("block"),
        move |vm: &mut VirtualMachine,
              _exec_scopes: &mut ExecutionScopes,
              ids_data: &HashMap<String, HintReference>,
              ap_tracking: &ApTracking,
              _constants: &HashMap<String, Felt252>|
              -> HintExecutionResult {
            // Add memory segment for the block payload in the VM.
            let base = keth_payload.gen_arg(vm)?;

            // Assign the base pointer to the block variable.
            insert_value_from_var_name("block", base, vm, ids_data, ap_tracking)?;

            Ok(())
        },
    )
}

/// Generates a placeholder hint for `dict_manager`.
pub fn dict_manager_hint() -> Hint {
    Hint::new(
        String::from("dict_manager"),
        |_vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> HintExecutionResult {
            // Placeholder logic for dict_manager
            Ok(())
        },
    )
}

/// Generates a placeholder hint for account.
pub fn account_hint() -> Hint {
    Hint::new(
        String::from("account"),
        |_vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> HintExecutionResult {
            // Placeholder logic for account
            Ok(())
        },
    )
}

/// Generates a placeholder hint for state.
pub fn state_hint() -> Hint {
    Hint::new(
        String::from("state"),
        |_vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> HintExecutionResult {
            // Placeholder logic for state
            Ok(())
        },
    )
}

/// Generates a placeholder hint for `chain_id`.
pub fn chain_id_hint() -> Hint {
    Hint::new(
        String::from("chain_id"),
        |_vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> HintExecutionResult {
            // Placeholder logic for chain_id
            Ok(())
        },
    )
}

/// Generates a placeholder hint for `dict_copy`.
pub fn dict_copy_hint() -> Hint {
    Hint::new(
        String::from("dict_copy"),
        |_vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> HintExecutionResult {
            // Placeholder logic for dict_copy
            Ok(())
        },
    )
}

/// Generates a placeholder hint for `dict_squash`.
pub fn dict_squash_hint() -> Hint {
    Hint::new(
        String::from("dict_squash"),
        |_vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> HintExecutionResult {
            // Placeholder logic for dict_squash
            Ok(())
        },
    )
}

/// Generates a placeholder hint for `block_hashes`.
pub fn block_hashes_hint() -> Hint {
    Hint::new(
        String::from("block_hashes"),
        |_vm: &mut VirtualMachine,
         _exec_scopes: &mut ExecutionScopes,
         _ids_data: &HashMap<String, HintReference>,
         _ap_tracking: &ApTracking,
         _constants: &HashMap<String, Felt252>|
         -> HintExecutionResult {
            // Placeholder logic for block_hashes
            Ok(())
        },
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use arbitrary::{Arbitrary, Unstructured};
    use cairo_vm::{
        cairo_run::{cairo_run, CairoRunConfig},
        types::layout_name::LayoutName,
    };
    use std::path::PathBuf;

    #[test]
    fn test_block_hint() {
        // Load the cairo program from the file
        let program =
            std::fs::read(PathBuf::from("../../cairo/tests/programs/test_os.json")).unwrap();

        // Initialize the Cairo run configuration
        let config = CairoRunConfig {
            layout: LayoutName::all_cairo,
            trace_enabled: true,
            relocate_mem: true,
            proof_mode: true,
            entrypoint: "test_block_hint",
            ..Default::default()
        };

        // Prepare a random byte array for testing
        let raw_bytes = [0u8; 1500];
        let mut unstructured = Unstructured::new(&raw_bytes);

        // Generate an arbitrary `SealedBlock`
        let block: SealedBlock = SealedBlock::arbitrary(&mut unstructured)
            .expect("Failed to generate arbitrary SealedBlock");

        // Build the Kakarot hint processor.
        let mut hint_processor = KakarotHintProcessor::default().with_block(block).build();

        // Execute the Kakarot os program
        let _res = cairo_run(&program, &config, &mut hint_processor)
            .expect("The program should run properly");
    }
}
