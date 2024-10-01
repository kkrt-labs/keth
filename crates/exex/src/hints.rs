use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::{
            builtin_hint_processor_definition::{BuiltinHintProcessor, HintFunc},
            memcpy_hint_utils::add_segment,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::ApTracking,
    types::{exec_scope::ExecutionScopes, relocatable::MaybeRelocatable},
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use reth_primitives::{Address, Bloom, Bytes, SealedBlock, Signature, B256, U256};
use std::{
    collections::HashMap,
    fmt,
    ops::{Deref, DerefMut},
    rc::Rc,
};

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
pub trait CairoSerializableBlock {
    /// Converts the block header to a vector of [`MaybeRelocatable`] elements.
    ///
    /// This method serializes the block header into a format that can be used within the Cairo VM.
    /// The output is a `KethPayload` that represents the fields of the block header.
    ///
    /// # Returns
    /// A `KethPayload` containing the serialized block header data.
    fn to_cairo_vm_block_header(&self) -> KethPayload;

    /// Converts the block body to a vector of [`MaybeRelocatable`] elements.
    ///
    /// This method serializes the block body, including transactions, into a format compatible with
    /// the Cairo VM. Each transaction is encoded and transformed into [`MaybeRelocatable`]
    /// elements.
    ///
    /// # Returns
    /// A `KethPayload` containing the serialized block body data, including transactions.
    fn to_cairo_vm_block_body(&self) -> KethPayload;

    /// Converts the entire block (header and body) into a single vector of [`MaybeRelocatable`]
    /// elements.
    ///
    /// This method combines the serialized block header and block body into one
    /// `KethPayload` to represent the full block in a format usable by the Cairo VM.
    ///
    /// # Returns
    /// A `KethPayload` containing the serialized block header and body data.
    fn to_cairo_vm_block(&self) -> KethPayload {
        let mut block = self.to_cairo_vm_block_header();
        block.0.extend(self.to_cairo_vm_block_body().0);
        block
    }
}

/// A wrapper around a vector of [`MaybeRelocatable`] elements to represent a serialized block.
#[derive(Debug)]
pub struct KethPayload(Vec<MaybeRelocatable>);

impl KethPayload {
    fn from_iter<I>(iter: I) -> Self
    where
        I: IntoIterator<Item = MaybeRelocatable>,
    {
        Self(iter.into_iter().collect())
    }
}

impl Deref for KethPayload {
    type Target = Vec<MaybeRelocatable>;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for KethPayload {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

impl From<Vec<MaybeRelocatable>> for KethPayload {
    fn from(value: Vec<MaybeRelocatable>) -> Self {
        Self(value)
    }
}

impl From<MaybeRelocatable> for KethPayload {
    fn from(value: MaybeRelocatable) -> Self {
        vec![value].into()
    }
}

impl From<u64> for KethPayload {
    fn from(value: u64) -> Self {
        MaybeRelocatable::from(Felt252::from(value)).into()
    }
}

impl From<Option<u64>> for KethPayload {
    fn from(value: Option<u64>) -> Self {
        MaybeRelocatable::from(Felt252::from(value.unwrap_or_default())).into()
    }
}

impl From<usize> for KethPayload {
    fn from(value: usize) -> Self {
        MaybeRelocatable::from(Felt252::from(value)).into()
    }
}

impl From<Bloom> for KethPayload {
    fn from(value: Bloom) -> Self {
        vec![
            MaybeRelocatable::from(Felt252::from(value.len())),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&value.0 .0)),
        ]
        .into()
    }
}

impl From<Address> for KethPayload {
    fn from(value: Address) -> Self {
        MaybeRelocatable::from(Felt252::from_bytes_be_slice(&value.0 .0)).into()
    }
}

impl From<U256> for KethPayload {
    fn from(value: U256) -> Self {
        MaybeRelocatable::from(Felt252::from_bytes_be_slice(
            &value.to_be_bytes::<{ U256::BYTES }>(),
        ))
        .into()
    }
}

impl From<Bytes> for KethPayload {
    fn from(value: Bytes) -> Self {
        vec![
            MaybeRelocatable::from(Felt252::from(value.len())),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&value.0)),
        ]
        .into()
    }
}

impl From<Vec<u8>> for KethPayload {
    fn from(value: Vec<u8>) -> Self {
        vec![
            MaybeRelocatable::from(Felt252::from(value.len())),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&value)),
        ]
        .into()
    }
}

impl From<B256> for KethPayload {
    fn from(value: B256) -> Self {
        vec![
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&value.0[16..])),
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&value.0[0..16])),
        ]
        .into()
    }
}

impl From<Option<B256>> for KethPayload {
    fn from(value: Option<B256>) -> Self {
        value.unwrap_or_default().into()
    }
}

impl From<Signature> for KethPayload {
    fn from(value: Signature) -> Self {
        vec![
            // The length of the signature payload
            MaybeRelocatable::from(Felt252::from(value.payload_len())),
            // The signature payload
            MaybeRelocatable::from(Felt252::from_bytes_be_slice(&value.to_bytes())),
        ]
        .into()
    }
}

impl CairoSerializableBlock for SealedBlock {
    fn to_cairo_vm_block_header(&self) -> KethPayload {
        // Get the header from the block
        let header = &self.header;

        // Serialize the header fields into [`MaybeRelocatable`] elements
        let serialized_header: Vec<KethPayload> = vec![
            header.base_fee_per_gas.into(),
            header.blob_gas_used.into(),
            header.logs_bloom.into(),
            header.beneficiary.into(),
            header.difficulty.into(),
            header.excess_blob_gas.into(),
            header.extra_data.clone().into(),
            header.gas_limit.into(),
            header.gas_used.into(),
            header.hash().into(),
            header.mix_hash.into(),
            header.nonce.into(),
            header.number.into(),
            header.parent_beacon_block_root.into(),
            header.parent_hash.into(),
            header.receipts_root.into(),
            header.state_root.into(),
            header.timestamp.into(),
            header.transactions_root.into(),
            header.ommers_hash.into(),
            header.withdrawals_root.into(),
        ];

        // Flatten the serialized header into a single vector
        KethPayload::from_iter(serialized_header.into_iter().flat_map(|field| field.0))
    }

    fn to_cairo_vm_block_body(&self) -> KethPayload {
        // The first element is the length of the body (number of transactions)
        let mut block_body: Vec<KethPayload> = vec![self.body.len().into()];

        self.body.iter().for_each(|transaction| {
            // RLP encode the transaction
            let mut buf = Vec::new();
            transaction.encode_without_signature(&mut buf);
            // Add the transaction and its signature to the block body
            block_body.extend([buf.into(), transaction.signature.into()]);
        });

        // Flatten the serialized block body into a single vector
        KethPayload::from_iter(block_body.into_iter().flat_map(|field| field.0))
    }
}

impl From<SealedBlock> for KethPayload {
    fn from(block: SealedBlock) -> Self {
        block.to_cairo_vm_block()
    }
}

pub fn block_hint(block: SealedBlock) -> Hint {
    Hint::new(
        String::from("block"),
        move |vm: &mut VirtualMachine,
              _exec_scopes: &mut ExecutionScopes,
              _ids_data: &HashMap<String, HintReference>,
              _ap_tracking: &ApTracking,
              _constants: &HashMap<String, Felt252>|
              -> HintExecutionResult {
            // This call will first add a new memory segment to the VM (the base)
            // Then we load the block into the VM starting from the base
            vm.gen_arg(&Into::<KethPayload>::into(block.clone()).0)?;

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
            let mut hint_processor = KakarotHintProcessor::default().with_block(block).build();

            // Load the cairo program from the file
            let program = std::fs::read(PathBuf::from("../../cairo/programs/block.json")).unwrap();

            // Run the cairo program with the hint processor and the block
            //
            // We unwrap the result to ensure that the program ran successfully
            let _ = cairo_run(&program, &config, &mut hint_processor).unwrap();
        }
    }
}
