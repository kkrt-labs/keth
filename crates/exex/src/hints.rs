use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::{
            builtin_hint_processor_definition::{BuiltinHintProcessor, HintFunc},
            hint_utils::get_ptr_from_var_name,
            memcpy_hint_utils::add_segment,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::{exec_scope::ExecutionScopes, relocatable::MaybeRelocatable},
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use reth_primitives::{SealedBlock, U256};
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
        Self::new_empty().with_hint(add_segment_hint())
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
    pub fn with_hint(mut self, hint: Hint) -> Self {
        self.processor.add_hint(hint.name.clone(), hint.func.clone());
        self
    }

    /// Returns the underlying [`BuiltinHintProcessor`].
    ///
    /// This allows the processor to be used elsewhere.
    pub fn build(self) -> BuiltinHintProcessor {
        self.processor
    }

    /// Adds a block to the [`KakarotHintProcessor`].
    pub fn with_block(self, block: SealedBlock) -> Self {
        self.with_hint(block_hint(block))
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

/// Trait representing a block that can be serialized into a format compatible with Cairo VM.
pub trait KethBlock {
    /// Converts the block header to a vector of `MaybeRelocatable` elements.
    ///
    /// This method serializes the block header into a format that can be used within the Cairo VM.
    /// The output is a `Vec<MaybeRelocatable>` that represents the fields of the block header.
    ///
    /// # Returns
    /// A `Vec<MaybeRelocatable>` containing the serialized block header data.
    fn to_cairo_vm_block_header(&self) -> Vec<MaybeRelocatable>;

    /// Converts the block body to a vector of `MaybeRelocatable` elements.
    ///
    /// This method serializes the block body, including transactions, into a format compatible with
    /// the Cairo VM. Each transaction is encoded and transformed into `MaybeRelocatable` elements.
    ///
    /// # Returns
    /// A `Vec<MaybeRelocatable>` containing the serialized block body data, including transactions.
    fn to_cairo_vm_block_body(&self) -> Vec<MaybeRelocatable>;

    /// Converts the entire block (header and body) into a single vector of `MaybeRelocatable`
    /// elements.
    ///
    /// This method combines the serialized block header and block body into one
    /// `Vec<MaybeRelocatable>` to represent the full block in a format usable by the Cairo VM.
    ///
    /// # Returns
    /// A `Vec<MaybeRelocatable>` containing the serialized block header and body data.
    fn to_cairo_vm_block(&self) -> Vec<MaybeRelocatable> {
        [self.to_cairo_vm_block_header(), self.to_cairo_vm_block_body()].concat()
    }
}

impl KethBlock for SealedBlock {
    fn to_cairo_vm_block_header(&self) -> Vec<MaybeRelocatable> {
        // Get the header from the block
        let header = &self.header;

        // Serialize the header fields into `MaybeRelocatable` elements
        vec![
            MaybeRelocatable::from(Felt252::from(header.base_fee_per_gas.unwrap_or_default())),
            MaybeRelocatable::from(Felt252::from(header.blob_gas_used.unwrap_or_default())),
            MaybeRelocatable::from(Felt252::from(header.logs_bloom.len())),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.logs_bloom.0 .0)),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.beneficiary.0 .0)),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.difficulty.to_be_bytes::<{ U256::BYTES }>(),
            )),
            MaybeRelocatable::from(Felt252::from(header.excess_blob_gas.unwrap_or_default())),
            MaybeRelocatable::from(Felt252::from(header.extra_data.len())),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.extra_data.0)),
            MaybeRelocatable::from(Felt252::from(header.gas_limit)),
            MaybeRelocatable::from(Felt252::from(header.gas_used)),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.hash().0[16..])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.hash().0[0..16])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.mix_hash.0[16..])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.mix_hash.0[0..16])),
            MaybeRelocatable::from(Felt252::from(header.nonce)),
            MaybeRelocatable::from(Felt252::from(header.number)),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.parent_beacon_block_root.unwrap_or_default().0[16..],
            )),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.parent_beacon_block_root.unwrap_or_default().0[0..16],
            )),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.parent_hash.0[16..])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.parent_hash.0[0..16])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.receipts_root.0[16..])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.receipts_root.0[0..16])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.state_root.0[16..])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.state_root.0[0..16])),
            MaybeRelocatable::from(Felt252::from(header.timestamp)),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.transactions_root.0[16..])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.transactions_root.0[0..16],
            )),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.ommers_hash.0[16..])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&header.ommers_hash.0[0..16])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.withdrawals_root.unwrap_or_default().0[16..],
            )),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                &header.withdrawals_root.unwrap_or_default().0[0..16],
            )),
        ]
    }

    fn to_cairo_vm_block_body(&self) -> Vec<MaybeRelocatable> {
        // The first element is the length of the body (number of transactions)
        let mut block_body = vec![MaybeRelocatable::from(Felt252::from(self.body.len()))];

        self.body.iter().for_each(|transaction| {
            // RLP encode the transaction
            let mut buf = Vec::new();
            transaction.encode_without_signature(&mut buf);

            block_body.extend([
                // The length of the RLP encoded transaction
                MaybeRelocatable::from(Felt252::from(buf.len())),
                // The RLP encoded transaction
                MaybeRelocatable::from(Felt252::from_bytes_be_slice(&buf)),
                // The length of the signature payload
                MaybeRelocatable::from(Felt252::from(transaction.signature.payload_len())),
                // The signature payload
                MaybeRelocatable::from(Felt252::from_bytes_be_slice(
                    &transaction.signature.to_bytes(),
                )),
            ]);
        });

        block_body
    }
}

pub fn block_hint(block: SealedBlock) -> Hint {
    Hint::new(
        String::from("block"),
        move |vm: &mut VirtualMachine,
              _exec_scopes: &mut ExecutionScopes,
              ids_data: &HashMap<String, HintReference>,
              ap_tracking: &ApTracking,
              _constants: &HashMap<String, Felt252>|
              -> HintExecutionResult {
            // We retrieve the `model.Block*` pointer from the `ids_data` hashmap.
            // This pointer is used to store the block-related values in the VM.
            let block_ptr = get_ptr_from_var_name("block", vm, ids_data, ap_tracking)?;

            vm.load_data(block_ptr, &block.to_cairo_vm_block()).map_err(HintError::Memory)?;

            Ok(())
        },
    )
}

#[cfg(test)]
mod test {
    use std::path::PathBuf;

    use super::*;
    use cairo_vm::{
        cairo_run::{cairo_run, CairoRunConfig},
        types::layout_name::LayoutName,
    };
    use reth_testing_utils::generators::{self, random_block, BlockParams, Rng};

    #[test]
    fn test_block_hint() {
        for _ in 0..10 {
            // Generate a random block
            let mut rng = generators::rng();
            let parent = rng.gen();
            let tx_count = Some(rng.gen::<u8>());
            let withdrawals_count = Some(rng.gen::<u8>());
            let ommers_count = Some(rng.gen::<u8>());
            let requests_count = Some(rng.gen::<u8>());
            let block = random_block(
                &mut rng,
                10,
                BlockParams {
                    parent: Some(parent),
                    tx_count,
                    withdrawals_count,
                    ommers_count,
                    requests_count,
                },
            );

            // Create a new cairo run configuration with the all_cairo layout
            let config = CairoRunConfig { layout: LayoutName::all_cairo, ..Default::default() };

            // Create a new hint processor with the block hint
            let mut hint_processor =
                KakarotHintProcessor::default().with_block(block.clone()).build();

            // Load the cairo program from the file
            let program = std::fs::read(PathBuf::from("../../cairo/programs/block.json")).unwrap();

            // Run the cairo program with the hint processor and the block
            //
            // We unwrap the result to ensure that the program ran successfully
            let _ = cairo_run(&program, &config, &mut hint_processor).unwrap();
        }
    }
}
