use super::{block::KethBlock, header::KethBlockHeader, transaction::KethTransactionEncoded};
use cairo_vm::{
    types::relocatable::MaybeRelocatable,
    vm::{errors::memory_errors::MemoryError, vm_core::VirtualMachine},
};
use serde::{Deserialize, Serialize};

/// A custom trait for encoding types into a vector of [`MaybeRelocatable`] values.
pub trait KethEncodable {
    /// Encodes the type into a [`KethPayload`] (a vector of [`MaybeRelocatable`] values).
    fn encode(&self) -> KethPayload;
}

/// Represents a payload in the Keth context.
///
/// This structure is designed for use in the Keth execution environment,
/// particularly in the context of encoding data for compatibility with Cairo VM.
///
/// This structure is recursive, enabling complex, nested encodings.
#[derive(Debug, Eq, PartialEq, Clone, Serialize, Deserialize)]
pub enum KethPayload {
    /// A classic payload with a vector of [`MaybeRelocatable`] values.
    Flat(Vec<MaybeRelocatable>),

    /// An optional value encoded with a flag indicating presence.
    ///
    /// - `is_some`: Indicates whether the value is present (`1`) or absent (`0`).
    /// - `value`: The actual value if present, wrapped in a [`KethPayload`].
    Option {
        /// Presence flag.
        is_some: MaybeRelocatable,
        /// The optional value.
        value: Box<KethPayload>,
    },

    /// A pointer to a segment of memory with associated data.
    ///
    /// - `len`: The length of the data segment (if the size can be variable).
    /// - `data`: The data itself, encoded as another [`KethPayload`].
    Pointer {
        /// The length of the pointer data.
        len: Option<MaybeRelocatable>,
        /// The data segment associated with this pointer.
        data: Box<KethPayload>,
    },

    /// A complex payload that encapsulates a vector of other [`KethPayload`] objects.
    ///
    /// This variant enables encoding of deeply nested or structured data,
    /// where each element can itself be a [`KethPayload`].
    Nested(Vec<KethPayload>),
}

impl KethPayload {
    /// Returns the inner vector of [`KethPayload`] values if the payload is of type `Nested`.
    pub fn as_nested_vec(&self) -> Option<Vec<Self>> {
        match self {
            Self::Nested(payloads) => Some(payloads.clone()),
            _ => None,
        }
    }

    /// Recursively collects arguments from a [`KethPayload`] into a flat vector.
    ///
    /// This function processes each variant of [`KethPayload`], flattening all nested structures
    /// into a single vector of [`MaybeRelocatable`] values that can be used to interact with the
    /// VM.
    fn collect_args(&self, vm: &mut VirtualMachine) -> Result<Vec<MaybeRelocatable>, MemoryError> {
        match self {
            // For the Flat variant, clone the values into the result vector.
            Self::Flat(values) => Ok(values.clone()),
            // For the Option variant:
            // - Add the `is_some` flag to the result vector.
            // - Recursively process the inner `value` and append its arguments.
            Self::Option { is_some, value } => {
                let mut args = vec![is_some.clone()];
                args.extend(value.collect_args(vm)?);
                Ok(args)
            }
            // For the Pointer variant:
            // - Generate arguments for the `data` payload using the VM.
            // - Include the `len` value (if available) and the generated data pointer.
            Self::Pointer { len, data } => Ok(if let Some(len) = len {
                vec![len.clone(), data.gen_arg(vm)?]
            } else {
                vec![data.gen_arg(vm)?]
            }),
            // For the Nested variant:
            // - Iterate through all inner payloads.
            // - Recursively collect arguments for each payload and flatten the results.
            Self::Nested(values) => {
                let mut args = Vec::new();
                for value in values {
                    args.extend(value.collect_args(vm)?);
                }
                Ok(args)
            }
        }
    }

    /// Encodes the [`KethPayload`] into the virtual machine's memory.
    ///
    /// This function uses `collect_args` to recursively flatten the payload into a vector
    /// and then writes the arguments to the VM's memory, returning a pointer to the encoded
    /// segment.
    pub fn gen_arg(&self, vm: &mut VirtualMachine) -> Result<MaybeRelocatable, MemoryError> {
        // Recursively collect arguments from the payload.
        let args = self.collect_args(vm)?;

        // Write the collected arguments into the VM's memory and return the resulting pointer.
        vm.gen_arg(&args)
    }
}

impl From<KethBlockHeader> for KethPayload {
    fn from(header: KethBlockHeader) -> Self {
        Self::Pointer {
            len: None,
            data: Box::new(Self::Nested(vec![
                header.parent_hash.encode(),
                header.ommers_hash.encode(),
                header.coinbase.encode(),
                header.state_root.encode(),
                header.transactions_root.encode(),
                header.receipt_root.encode(),
                header.withdrawals_root.encode(),
                header.bloom.encode(),
                header.difficulty.encode(),
                header.number.encode(),
                header.gas_limit.encode(),
                header.gas_used.encode(),
                header.timestamp.encode(),
                header.mix_hash.encode(),
                header.nonce.encode(),
                header.base_fee_per_gas.encode(),
                header.blob_gas_used.encode(),
                header.excess_blob_gas.encode(),
                header.parent_beacon_block_root.encode(),
                header.requests_root.encode(),
                header.extra_data.encode(),
            ])),
        }
    }
}

impl From<KethTransactionEncoded> for KethPayload {
    fn from(transaction: KethTransactionEncoded) -> Self {
        Self::Nested(vec![
            transaction.rlp.encode(),
            transaction.signature.encode(),
            transaction.sender.encode(),
        ])
    }
}

impl From<KethBlock> for KethPayload {
    fn from(block: KethBlock) -> Self {
        Self::Nested(vec![
            block.block_header.into(),
            block.transactions_len.encode(),
            Self::Pointer {
                len: None,
                data: Box::new(Self::Nested(
                    block.transactions.into_iter().map(Into::into).collect(),
                )),
            },
        ])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::primitives::{KethMaybeRelocatable, KethOption, KethPointer, KethU256};
    use alloy_consensus::{Header, TxLegacy};
    use alloy_primitives::{
        hex, Address, Bloom, Bytes, Parity, PrimitiveSignature, B256, B64, U256,
    };
    use arbitrary::{Arbitrary, Unstructured};
    use cairo_vm::{types::relocatable::Relocatable, Felt252};
    use reth_primitives::{
        BlockBody, SealedBlock, SealedHeader, Transaction, TransactionSigned,
        TransactionSignedNoHash,
    };
    use std::str::FromStr;

    #[test]
    #[allow(clippy::too_many_lines, clippy::cognitive_complexity)]
    fn test_keth_block_header_to_payload() {
        // Create realistic non-default values for the fields
        let parent_hash = B256::from([0x11u8; 32]);
        let ommers_hash = B256::from([0x22u8; 32]);
        let coinbase = Address::new([0x33u8; 20]);
        let state_root = B256::from([0x44u8; 32]);
        let transactions_root = B256::from([0x55u8; 32]);
        let receipt_root = B256::from([0x66u8; 32]);
        let withdrawals_root = Some(B256::from([0x77u8; 32]));
        let bloom = Bloom::from_slice(&[0x88u8; 256]);
        let difficulty = U256::from(999_999_999_u64);
        let number = 123_456_u64;
        let gas_limit = 8_000_000_u64;
        let gas_used = 7_500_000_u64;
        let timestamp = 1_630_000_000_u64;
        let mix_hash = B256::from([0x99u8; 32]);
        let nonce = 42u64;
        let base_fee_per_gas = Some(100u64);
        let blob_gas_used = Some(200u64);
        let excess_blob_gas = Some(300u64);
        let parent_beacon_block_root = Some(B256::from([0xAAu8; 32]));
        let requests_root = Some(B256::from([0xBBu8; 32]));
        let extra_data = Bytes::from(vec![0xCC, 0xDD, 0xEE, 0xFF]);

        // Construct a Header using the values
        let header = Header {
            parent_hash,
            ommers_hash,
            beneficiary: coinbase,
            state_root,
            transactions_root,
            receipts_root: receipt_root,
            withdrawals_root,
            logs_bloom: bloom,
            difficulty,
            number,
            gas_limit,
            gas_used,
            timestamp,
            mix_hash,
            nonce: nonce.into(),
            base_fee_per_gas,
            blob_gas_used,
            excess_blob_gas,
            parent_beacon_block_root,
            requests_hash: requests_root,
            extra_data: extra_data.clone(),
        };

        // Convert to KethBlockHeader
        let keth_header: KethBlockHeader = header.into();

        // Convert KethBlockHeader to payload
        let payload: KethPayload = keth_header.into();

        // Ensure the payload is of the Nested variant
        if let KethPayload::Pointer { data, .. } = payload {
            let fields = data.as_nested_vec().expect("Fields should be nested");

            // Verify each field individually by reconstructing the expected payloads
            let expected_fields = vec![
                KethU256::from(parent_hash).encode(),
                KethU256::from(ommers_hash).encode(),
                KethMaybeRelocatable::from(coinbase).encode(),
                KethU256::from(state_root).encode(),
                KethU256::from(transactions_root).encode(),
                KethU256::from(receipt_root).encode(),
                KethOption::<KethPointer>::from(withdrawals_root).encode(),
                KethPointer::from(bloom).encode(),
                KethU256::from(difficulty).encode(),
                KethMaybeRelocatable::from(number).encode(),
                KethMaybeRelocatable::from(gas_limit).encode(),
                KethMaybeRelocatable::from(gas_used).encode(),
                KethMaybeRelocatable::from(timestamp).encode(),
                KethU256::from(mix_hash).encode(),
                KethMaybeRelocatable::from(nonce).encode(),
                KethOption::<KethMaybeRelocatable>::from(base_fee_per_gas).encode(),
                KethOption::<KethMaybeRelocatable>::from(blob_gas_used).encode(),
                KethOption::<KethMaybeRelocatable>::from(excess_blob_gas).encode(),
                KethOption::<KethPointer>::from(parent_beacon_block_root).encode(),
                KethOption::<KethPointer>::from(requests_root).encode(),
                KethPointer::from(extra_data).encode(),
            ];

            assert_eq!(fields.len(), expected_fields.len(), "Field count mismatch in payload");

            for (actual, expected) in fields.iter().zip(expected_fields.iter()) {
                assert_eq!(actual, expected, "Field mismatch in payload");
            }
        } else {
            panic!("Expected payload to be of type Pointer");
        }
    }

    #[test]
    fn test_keth_transaction_encoded_to_payload_arbitrary() {
        // Generate arbitrary raw bytes
        let raw_bytes = [0u8; 1000];
        let mut unstructured = Unstructured::new(&raw_bytes);

        // Generate an arbitrary signed transaction
        let tx = TransactionSigned::arbitrary(&mut unstructured)
            .expect("Failed to generate arbitrary transaction");

        // Convert the signed transaction into KethTransactionEncoded
        let keth_transaction_encoded =
            KethTransactionEncoded::try_from(tx).expect("Failed to convert transaction");

        // Convert KethTransactionEncoded into KethPayload
        let payload: KethPayload = keth_transaction_encoded.clone().into();

        // Ensure the payload is of the Nested variant
        if let KethPayload::Nested(fields) = payload {
            assert_eq!(fields.len(), 3, "Payload should contain 3 fields (RLP, signature, sender)");

            // Verify each field
            let encoded_rlp = keth_transaction_encoded.rlp.encode();
            let encoded_signature = keth_transaction_encoded.signature.encode();
            let encoded_sender = keth_transaction_encoded.sender.encode();

            assert_eq!(&fields[0], &encoded_rlp, "RLP field mismatch in payload");

            assert_eq!(&fields[1], &encoded_signature, "Signature field mismatch in payload");

            assert_eq!(&fields[2], &encoded_sender, "Sender field mismatch in payload");
        } else {
            panic!("Expected payload to be of type Nested");
        }
    }

    #[test]
    fn test_keth_block_to_payload_conversion() {
        // Generate arbitrary data for testing
        let raw_bytes = [0u8; 1500];
        let mut unstructured = Unstructured::new(&raw_bytes);

        // Create an arbitrary SealedBlock
        let sealed_block: SealedBlock = SealedBlock::arbitrary(&mut unstructured)
            .expect("Failed to generate arbitrary SealedBlock");

        // Convert the SealedBlock into a KethBlock
        let keth_block: KethBlock = sealed_block.into();

        // Convert the KethBlock into KethPayload
        let payload: KethPayload = keth_block.clone().into();

        // Ensure the payload is of the Nested variant
        if let KethPayload::Nested(fields) = payload {
            // Check that the payload contains exactly 3 elements
            assert_eq!(fields.len(), 3, "Payload should contain 3 top-level elements");

            // Verify the block header is encoded
            let header_payload = KethPayload::from(keth_block.block_header);
            assert_eq!(fields[0], header_payload, "Block header payload mismatch");

            // Verify the transactions_len field is encoded
            let transactions_len_payload = keth_block.transactions_len.encode();
            assert_eq!(fields[1], transactions_len_payload, "Transaction length payload mismatch");

            // Verify the transactions are encoded
            if let KethPayload::Pointer { data, .. } = &fields[2] {
                let transaction_fields =
                    data.as_nested_vec().expect("Transaction fields should be nested");

                assert_eq!(
                    transaction_fields.len(),
                    keth_block.transactions.len(),
                    "Number of transactions in payload mismatch"
                );

                // Check each transaction
                for (i, keth_tx) in keth_block.transactions.iter().enumerate() {
                    let transaction_payload = KethPayload::from(keth_tx.clone());
                    assert_eq!(
                        transaction_fields[i], transaction_payload,
                        "Transaction payload mismatch at index {i}"
                    );
                }
            } else {
                panic!("Expected Pointer payload for transactions");
            }
        } else {
            panic!("Expected Nested payload at top level");
        }
    }

    #[test]
    fn test_gen_arg_flat() {
        // Create a new instance of the VirtualMachine.
        let mut vm = VirtualMachine::new(false);

        // Define a flat payload with three Felt values.
        let values =
            vec![MaybeRelocatable::from(1), MaybeRelocatable::from(2), MaybeRelocatable::from(3)];

        // Wrap the values in a KethPayload::Flat variant.
        let payload = KethPayload::Flat(values.clone());

        // Call gen_arg to encode the payload and write it to the VM's memory.
        let result = payload.gen_arg(&mut vm);

        // Ensure that the gen_arg call succeeded.
        assert!(result.is_ok(), "Expected gen_arg to succeed");

        // Retrieve the resulting pointer to the memory segment where the payload was written.
        let ptr = result.unwrap();

        // Verify that the pointer points to the start of the new segment (0, 0).
        assert_eq!(ptr, MaybeRelocatable::from((0, 0)), "Expected pointer to start of segment");

        // Check each value in the payload to ensure it matches the expected values.
        for (i, value) in values.iter().enumerate() {
            assert_eq!(
                vm.get_maybe(&Relocatable::from((0, i))),
                Some(value.clone()),
                "Value mismatch at index {i}"
            );
        }
    }

    #[test]
    fn test_gen_arg_option_some() {
        // Create a new instance of the VirtualMachine.
        let mut vm = VirtualMachine::new(false);

        // Define an Option payload with:
        // - A presence flag indicating the value is present
        // - A nested Flat payload containing a single relocatable value.
        let payload = KethPayload::Option {
            is_some: MaybeRelocatable::from(1),
            value: Box::new(KethPayload::Flat(vec![MaybeRelocatable::from(42)])),
        };

        // Call gen_arg to encode the payload and write it to the VM's memory.
        let result = payload.gen_arg(&mut vm);

        // Ensure that the gen_arg call succeeded and returned a valid pointer.
        assert!(result.is_ok(), "Expected gen_arg to succeed");

        // Retrieve the resulting pointer to the memory segment for the Option payload.
        let ptr = result.unwrap();

        // Verify that the pointer points to the start of the new segment (0, 0).
        assert_eq!(ptr, MaybeRelocatable::from((0, 0)));

        // Verify presence flag and value are written to the memory.
        assert_eq!(vm.get_maybe(&Relocatable::from((0, 0))), Some(MaybeRelocatable::from(1)));
        assert_eq!(vm.get_maybe(&Relocatable::from((0, 1))), Some(MaybeRelocatable::from(42)));
    }

    #[test]
    fn test_gen_arg_option_none() {
        // Create a new instance of the VirtualMachine.
        let mut vm = VirtualMachine::new(false);

        // Define an Option payload with a presence flag indicating the value is absent.
        // - The presence flag is set to `0` to indicate that the value is absent.
        // - The nested payload is an empty Flat variant.
        let payload = KethPayload::Option {
            is_some: MaybeRelocatable::from(0),
            value: Box::new(KethPayload::Flat(vec![])),
        };

        // Call gen_arg to encode the payload and write it to the VM's memory.
        let result = payload.gen_arg(&mut vm);

        // Ensure that the gen_arg call succeeded and returned a valid pointer.
        assert!(result.is_ok(), "Expected gen_arg to succeed");

        // Retrieve the resulting pointer to the memory segment for the Option payload.
        let ptr = result.unwrap();

        // Verify that the pointer points to the correct segment.
        assert_eq!(ptr, MaybeRelocatable::from((0, 0)));

        // Verify that the value of the option is None.
        assert_eq!(vm.get_maybe(&Relocatable::from((0, 0))), Some(MaybeRelocatable::from(0)));
        assert_eq!(vm.get_maybe(&Relocatable::from((0, 1))), None);
    }

    #[test]
    fn test_gen_arg_pointer() {
        // Create a new instance of the VirtualMachine.
        let mut vm = VirtualMachine::new(false);

        // Define a Pointer payload with a length and nested data.
        // - The length is set to 3.
        let payload = KethPayload::Pointer {
            len: Some(MaybeRelocatable::from(3)),
            data: Box::new(KethPayload::Flat(vec![
                MaybeRelocatable::from(1),
                MaybeRelocatable::from(2),
                MaybeRelocatable::from(3),
            ])),
        };

        // Call gen_arg to encode the payload and write it to the VM's memory.
        let result = payload.gen_arg(&mut vm);

        // Ensure that the gen_arg call succeeded and returned a valid pointer.
        assert!(result.is_ok(), "Expected gen_arg to succeed");

        // Retrieve the resulting pointer to the memory segment for the Pointer payload.
        let ptr = result.unwrap();

        // Verify that the pointer points to the start of the second segment (1, 0).
        assert_eq!(ptr, MaybeRelocatable::from((1, 0)), "Expected pointer to start of segment");

        // Verify that the length of the data segment is correctly written in the second segment.
        assert_eq!(vm.get_maybe(&Relocatable::from((1, 0))), Some(MaybeRelocatable::from(3)));

        // Verify that each data value is correctly written in memory.
        for (i, value) in [1, 2, 3].iter().enumerate() {
            assert_eq!(
                vm.get_maybe(&Relocatable::from((0, i))),
                Some(MaybeRelocatable::from(*value)),
                "Data value mismatch at index {i}"
            );
        }
    }

    #[test]
    fn test_gen_arg_nested() {
        // Create a new instance of the VirtualMachine.
        let mut vm = VirtualMachine::new(false);

        // Define a Nested payload containing three Flat payloads.
        let nested_payloads = vec![
            KethPayload::Flat(vec![MaybeRelocatable::from(10)]),
            KethPayload::Flat(vec![MaybeRelocatable::from(20)]),
            KethPayload::Flat(vec![MaybeRelocatable::from(30)]),
        ];

        // Wrap the nested payloads in a KethPayload::Nested variant.
        let payload = KethPayload::Nested(nested_payloads);

        // Call gen_arg to encode the payload and write it to the VM's memory.
        let result = payload.gen_arg(&mut vm);

        // Ensure that the gen_arg call succeeded and returned a valid pointer.
        assert!(result.is_ok(), "Expected gen_arg to succeed");

        // Retrieve the resulting pointer to the memory segment for the Nested payload.
        let ptr = result.unwrap();

        // Verify that the pointer points to the correct segment.
        assert_eq!(ptr, MaybeRelocatable::from((0, 0)), "Expected pointer to start of segment");

        // Verify that each nested payload is correctly written in memory.
        assert_eq!(vm.get_maybe(&Relocatable::from((0, 0))), Some(MaybeRelocatable::from(10)));
        assert_eq!(vm.get_maybe(&Relocatable::from((0, 1))), Some(MaybeRelocatable::from(20)));
        assert_eq!(vm.get_maybe(&Relocatable::from((0, 2))), Some(MaybeRelocatable::from(30)));
    }

    #[test]
    fn test_gen_arg_complex_nested() {
        // Create a new instance of the VirtualMachine.
        let mut vm = VirtualMachine::new(false);

        // Define a deeply nested payload with various combinations of:
        // - Flat,
        // - Option,
        // - Pointer.
        let complex_payload = KethPayload::Nested(vec![
            // First element: A Flat payload
            KethPayload::Flat(vec![MaybeRelocatable::from(1), MaybeRelocatable::from(2)]),
            // Second element: An Option payload containing a Flat payload
            KethPayload::Option {
                is_some: MaybeRelocatable::from(1),
                value: Box::new(KethPayload::Flat(vec![MaybeRelocatable::from(42)])),
            },
            // Third element: A Pointer payload with a nested Flat payload
            KethPayload::Pointer {
                len: Some(MaybeRelocatable::from(3)),
                data: Box::new(KethPayload::Flat(vec![
                    MaybeRelocatable::from(10),
                    MaybeRelocatable::from(20),
                    MaybeRelocatable::from(30),
                ])),
            },
        ]);

        // Call gen_arg to encode the complex payload and write it to the VM's memory.
        let result = complex_payload.gen_arg(&mut vm);

        // Ensure that the gen_arg call succeeded and returned a valid pointer.
        assert!(result.is_ok(), "Expected gen_arg to succeed");

        // Retrieve the resulting pointer to the memory segment for the complex Nested payload.
        let ptr = result.unwrap();

        // Verify that the pointer points to the start of the correct segment.
        assert_eq!(
            ptr,
            MaybeRelocatable::from((1, 0)),
            "Expected pointer to start of segment for complex nested payload"
        );

        // Verify the Flat payload
        assert_eq!(vm.get_maybe(&Relocatable::from((1, 0))), Some(MaybeRelocatable::from(1)));
        assert_eq!(vm.get_maybe(&Relocatable::from((1, 1))), Some(MaybeRelocatable::from(2)));

        // Verify the Option payload
        // The presence flag
        assert_eq!(vm.get_maybe(&Relocatable::from((1, 2))), Some(MaybeRelocatable::from(1)));
        // The value
        assert_eq!(vm.get_maybe(&Relocatable::from((1, 3))), Some(MaybeRelocatable::from(42)));

        // Verify the Pointer payload
        // The values
        assert_eq!(vm.get_maybe(&Relocatable::from((0, 0))), Some(MaybeRelocatable::from(10)));
        assert_eq!(vm.get_maybe(&Relocatable::from((0, 1))), Some(MaybeRelocatable::from(20)));
        assert_eq!(vm.get_maybe(&Relocatable::from((0, 2))), Some(MaybeRelocatable::from(30)));

        // The length
        assert_eq!(vm.get_maybe(&Relocatable::from((1, 4))), Some(MaybeRelocatable::from(3)));
        // The pointer to the data
        assert_eq!(vm.get_maybe(&Relocatable::from((1, 5))), Some(MaybeRelocatable::from((0, 0))));
    }

    #[test]
    #[allow(clippy::too_many_lines, clippy::cognitive_complexity, clippy::unnecessary_cast)]
    fn test_gen_arg_block() {
        // Initialize a new block header
        let header = Header {
            parent_hash: B256::from_str(
                "0x02a4bfb03275efd1bf926bcbccc1c12ef1ed723414c1196b75c33219355c7180",
            )
            .unwrap(),
            ommers_hash: B256::from_str(
                "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
            )
            .unwrap(),
            beneficiary: Address::from_str("0x2adc25665018aa1fe0e6bc666dac8fc2697ff9ba").unwrap(),
            state_root: B256::from_str(
                "0x2f79dbc20b78bcd7a771a9eb6b25a4af69724085c97be69a95ba91187e66a9c0",
            )
            .unwrap(),
            transactions_root: B256::from_str(
                "0x5f3c4c1da4f0b2351fbb60b9e720d481ce0706b5aa697f10f28efbbab54e6ac8",
            )
            .unwrap(),
            receipts_root: B256::from_str(
                "0xf44202824894394d28fa6c8c8e3ef83e1adf05405da06240c2ce9ca461e843d1",
            )
            .unwrap(),
            logs_bloom: Bloom::default(),
            difficulty: U256::ZERO,
            number: 1,
            gas_limit: 0x000f_4240,
            gas_used: 0x0001_56f8,
            timestamp: 0x6490_3c57,
            extra_data: Bytes::from_static(&hex!("00")),
            mix_hash: B256::from_str(
                "0x0000000000000000000000000000000000000000000000000000000000020000",
            )
            .unwrap(),
            nonce: B64::from_str("0x0000000000000000").unwrap(),
            base_fee_per_gas: Some(0x0a),
            withdrawals_root: Some(
                B256::from_str(
                    "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
                )
                .unwrap(),
            ),
            blob_gas_used: Some(0x00),
            excess_blob_gas: Some(0x00),
            parent_beacon_block_root: Some(
                B256::from_str(
                    "0x0000000000000000000000000000000000000000000000000000000000000000",
                )
                .unwrap(),
            ),
            requests_hash: None,
        };

        // Initialize the block hash
        let block_hash =
            B256::from_str("0x46e317ac1d4c1a14323d9ef994c0f0813c6a90af87113a872ca6bcfcea86edba")
                .unwrap();

        // Seal the header with the block hash
        let sealed_header = SealedHeader::new(header, block_hash);

        // Generate some transaction input bytes
        let transaction_data = Bytes::from_static(&hex!("000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));

        // Create a transaction with a signature but no hash
        let transaction_no_hash = TransactionSignedNoHash {
            transaction: Transaction::Legacy(TxLegacy {
                chain_id: None,
                nonce: 0x00,
                gas_price: 0x0a,
                gas_limit: 0x000f_4240,
                to: revm_primitives::TxKind::Call(
                    Address::from_str("0x000000000000000000000000000000000000c0de").unwrap(),
                ),
                value: U256::from(0x00),
                input: transaction_data,
            }),
            signature: PrimitiveSignature::from_scalars_and_parity(
                B256::from_str(
                    "0xf225c2292ba248fe3ed544f7d45dd4172337ba41dc480c3b17af63e03d281daf",
                )
                .unwrap(),
                B256::from_str(
                    "0x35360ae92ae767c1d0a9e0358e4398174b10eeea046bceedf323e7bf3b17c652",
                )
                .unwrap(),
                Parity::try_from(0x1c_u64).unwrap().y_parity(),
            ),
        };

        // Add the transaction hash
        let transaction = transaction_no_hash.with_hash();

        // Seal the block
        let sealed_block = SealedBlock {
            header: sealed_header,
            body: BlockBody {
                transactions: vec![transaction.clone(), transaction],
                ommers: vec![],
                withdrawals: Some(vec![].into()),
            },
        };

        // Transform the sealed block into a KethBlock
        let keth_block: KethBlock = sealed_block.into();

        // Transform the KethBlock into a KethPayload
        let keth_payload: KethPayload = keth_block.clone().into();

        // Create a new instance of the VirtualMachine.
        let mut vm = VirtualMachine::new(false);

        // Call gen_arg to encode the block payload and write it to the VM's memory.
        let result = keth_payload.gen_arg(&mut vm);

        // Retrieve the resulting pointer to the memory segment for the complex Nested payload.
        let ptr = match result.expect("Failed to gen_arg the block payload") {
            MaybeRelocatable::RelocatableValue(relocatable) => relocatable,
            MaybeRelocatable::Int(_) => panic!("Expected a valid pointer"),
        };

        // Extract the block header pointer
        let header_ptr = vm.get_maybe(&ptr).unwrap().get_relocatable().unwrap();

        // Transaction count
        assert_eq!(
            vm.get_maybe(&(ptr + 1usize).unwrap()),
            Some(keth_block.clone().transactions_len.0)
        );

        let transaction_ptr =
            vm.get_maybe(&(ptr + 2usize).unwrap()).unwrap().get_relocatable().unwrap();

        // Block header fields
        // The parent hash as U256:
        // - Low
        // - High
        assert_eq!(vm.get_maybe(&header_ptr), Some(keth_block.block_header.parent_hash.low.0));
        assert_eq!(
            vm.get_maybe(&(header_ptr + 1usize).unwrap()),
            Some(keth_block.block_header.parent_hash.high.0)
        );

        // The ommers hash as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 2usize).unwrap()),
            Some(keth_block.block_header.ommers_hash.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 3usize).unwrap()),
            Some(keth_block.block_header.ommers_hash.high.0)
        );

        // The beneficiary as Address with a single Felt
        assert_eq!(
            vm.get_maybe(&(header_ptr + 4usize).unwrap()),
            Some(keth_block.block_header.coinbase.0)
        );

        // The state root as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 5usize).unwrap()),
            Some(keth_block.block_header.state_root.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 6usize).unwrap()),
            Some(keth_block.block_header.state_root.high.0)
        );

        // The transactions root as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 7usize).unwrap()),
            Some(keth_block.block_header.transactions_root.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 8usize).unwrap()),
            Some(keth_block.block_header.transactions_root.high.0)
        );

        // The receipt root as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 9usize).unwrap()),
            Some(keth_block.block_header.receipt_root.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 10usize).unwrap()),
            Some(keth_block.block_header.receipt_root.high.0)
        );

        // The withdrawal root as an Option of U256*:
        // - is_some
        // - address of the U256
        assert_eq!(
            vm.get_maybe(&(header_ptr + 11usize).unwrap()),
            Some(keth_block.block_header.withdrawals_root.is_some.0)
        );

        let withdrawal_root_ptr =
            vm.get_maybe(&(header_ptr + 12usize).unwrap()).unwrap().get_relocatable().unwrap();

        // Withdrawal root U256 pointer:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&withdrawal_root_ptr),
            Some(keth_block.block_header.withdrawals_root.value.data[0].0.clone())
        );
        assert_eq!(
            vm.get_maybe(&(withdrawal_root_ptr + 1usize).unwrap()),
            Some(keth_block.block_header.withdrawals_root.value.data[1].0.clone())
        );
        assert_eq!(vm.get_maybe(&(withdrawal_root_ptr + 2usize).unwrap()), None);

        // The bloom as a pointer:
        // - The address at which the data are
        let bloom_ptr =
            vm.get_maybe(&(header_ptr + 13usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The Bloom data, as felt*
        for i in 0..16 {
            assert_eq!(
                vm.get_maybe(&(bloom_ptr + i as usize).unwrap()),
                Some(keth_block.block_header.bloom.data[i].0.clone())
            );
        }
        // After the last Bloom data index, the memory should be None.
        assert_eq!(vm.get_maybe(&(bloom_ptr + 16usize).unwrap()), None);

        // The difficulty as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 14usize).unwrap()),
            Some(keth_block.block_header.difficulty.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 15usize).unwrap()),
            Some(keth_block.block_header.difficulty.high.0)
        );

        // The block number as MaybeRelocatable:
        assert_eq!(
            vm.get_maybe(&(header_ptr + 16usize).unwrap()),
            Some(keth_block.block_header.number.0)
        );

        // The gas limit as MaybeRelocatable:
        assert_eq!(
            vm.get_maybe(&(header_ptr + 17usize).unwrap()),
            Some(keth_block.block_header.gas_limit.0)
        );

        // The gas used as MaybeRelocatable:
        assert_eq!(
            vm.get_maybe(&(header_ptr + 18usize).unwrap()),
            Some(keth_block.block_header.gas_used.0)
        );

        // The timestamp as MaybeRelocatable:
        assert_eq!(
            vm.get_maybe(&(header_ptr + 19usize).unwrap()),
            Some(keth_block.block_header.timestamp.0)
        );

        // The mix hash as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 20usize).unwrap()),
            Some(keth_block.block_header.mix_hash.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 21usize).unwrap()),
            Some(keth_block.block_header.mix_hash.high.0)
        );

        // The nonce as MaybeRelocatable:
        assert_eq!(
            vm.get_maybe(&(header_ptr + 22usize).unwrap()),
            Some(keth_block.block_header.nonce.0)
        );

        // The base fee per gas as an Option of MaybeRelocatable:
        // - is_some
        // - Value
        assert_eq!(
            vm.get_maybe(&(header_ptr + 23usize).unwrap()),
            Some(keth_block.block_header.base_fee_per_gas.is_some.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 24usize).unwrap()),
            Some(keth_block.block_header.base_fee_per_gas.value.0)
        );

        // The blob gas used as an Option of MaybeRelocatable:
        // - is_some
        // - Value
        assert_eq!(
            vm.get_maybe(&(header_ptr + 25usize).unwrap()),
            Some(keth_block.block_header.blob_gas_used.is_some.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 26usize).unwrap()),
            Some(keth_block.block_header.blob_gas_used.value.0)
        );

        // The excess blob gas as an Option of MaybeRelocatable:
        // - is_some
        // - Value
        assert_eq!(
            vm.get_maybe(&(header_ptr + 27usize).unwrap()),
            Some(keth_block.block_header.excess_blob_gas.is_some.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 28usize).unwrap()),
            Some(keth_block.block_header.excess_blob_gas.value.0)
        );

        // The parent beacon block root as an Option of U256*:
        // - is_some
        // - address of the U256
        assert_eq!(
            vm.get_maybe(&(header_ptr + 29usize).unwrap()),
            Some(keth_block.block_header.parent_beacon_block_root.is_some.0)
        );
        let parent_beacon_block_root_ptr =
            vm.get_maybe(&(header_ptr + 30usize).unwrap()).unwrap().get_relocatable().unwrap();

        // Parent Beacon Block Root U256 pointer:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&parent_beacon_block_root_ptr),
            Some(keth_block.block_header.parent_beacon_block_root.value.data[0].0.clone())
        );
        assert_eq!(
            vm.get_maybe(&(parent_beacon_block_root_ptr + 1usize).unwrap()),
            Some(keth_block.block_header.parent_beacon_block_root.value.data[1].0.clone())
        );
        assert_eq!(vm.get_maybe(&(parent_beacon_block_root_ptr + 2usize).unwrap()), None);

        // The requests root as an Option of U256*:
        // - is_some
        // - address of the U256
        assert_eq!(
            vm.get_maybe(&(header_ptr + 31usize).unwrap()),
            Some(keth_block.block_header.requests_root.is_some.0)
        );
        let requests_root_ptr =
            vm.get_maybe(&(header_ptr + 32usize).unwrap()).unwrap().get_relocatable().unwrap();

        // Requests Root U256 pointer (None in this case):
        // - Low
        // - High
        assert_eq!(vm.get_maybe(&requests_root_ptr), None);

        // The extra data pointer as KethPointer:
        // - Length
        // - Address
        assert_eq!(
            vm.get_maybe(&(header_ptr + 33usize).unwrap()),
            Some(keth_block.block_header.extra_data.len.unwrap().0)
        );
        let extra_data_ptr =
            vm.get_maybe(&(header_ptr + 34usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The Extra Data, as felt*, should be stored in the second segment of the memory.
        assert_eq!(
            vm.get_maybe(&extra_data_ptr),
            Some(keth_block.block_header.extra_data.data[0].0.clone())
        );
        // After the last Extra Data index, the memory should be None.
        assert_eq!(vm.get_maybe(&(extra_data_ptr + 1usize).unwrap()), None);

        // End of the header
        assert_eq!(vm.get_maybe(&(header_ptr + 35usize).unwrap()), None);

        // First transaction
        // Rlp of the transaction as a KethPointer:
        // - Length
        // - Address
        assert_eq!(
            vm.get_maybe(&transaction_ptr),
            Some(keth_block.transactions[0].rlp.len.clone().unwrap().0)
        );
        let transaction1_rlp_ptr =
            vm.get_maybe(&(transaction_ptr + 1usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The first transaction rlp, as felt*
        for i in 0..128 {
            assert_eq!(
                vm.get_maybe(&(transaction1_rlp_ptr + i as usize).unwrap()),
                Some(keth_block.transactions[0].rlp.data[i].0.clone())
            );
        }
        // After the last transaction rlp index, the memory should be None.
        assert_eq!(vm.get_maybe(&(transaction1_rlp_ptr + 128usize).unwrap()), None);

        // Transaction signature as a KethPointer:
        // - Length
        // - Address
        assert_eq!(
            vm.get_maybe(&(transaction_ptr + 2usize).unwrap()),
            Some(keth_block.transactions[0].signature.len.clone().unwrap().0)
        );
        let transaction1_signature_ptr =
            vm.get_maybe(&(transaction_ptr + 3usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The first transaction signature, as felt*
        for i in 0..5 {
            assert_eq!(
                vm.get_maybe(&(transaction1_signature_ptr + i as usize).unwrap()),
                Some(keth_block.transactions[0].signature.data[i].0.clone())
            );
        }
        // After the last transaction signature index, the memory should be None.
        assert_eq!(vm.get_maybe(&(transaction1_signature_ptr + 5usize).unwrap()), None);

        // Transaction sender as an address:
        assert_eq!(
            vm.get_maybe(&(transaction_ptr + 4usize).unwrap()),
            Some(keth_block.transactions[0].sender.0.clone())
        );

        // Second transaction
        // Rlp of the transaction as a KethPointer:
        // - Length
        // - Address
        assert_eq!(
            vm.get_maybe(&(transaction_ptr + 5usize).unwrap()),
            Some(keth_block.transactions[1].rlp.len.clone().unwrap().0)
        );
        let transaction2_rlp_ptr =
            vm.get_maybe(&(transaction_ptr + 6usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The second transaction rlp, as felt*
        for i in 0..128 {
            assert_eq!(
                vm.get_maybe(&(transaction2_rlp_ptr + i as usize).unwrap()),
                Some(keth_block.transactions[0].rlp.data[i].0.clone())
            );
        }
        // After the last transaction rlp index, the memory should be None.
        assert_eq!(vm.get_maybe(&(transaction2_rlp_ptr + 128usize).unwrap()), None);

        // Transaction signature as a KethPointer:
        // - Length
        // - Address
        assert_eq!(
            vm.get_maybe(&(transaction_ptr + 7usize).unwrap()),
            Some(keth_block.transactions[1].signature.len.clone().unwrap().0)
        );
        let transaction2_signature_ptr =
            vm.get_maybe(&(transaction_ptr + 8usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The first transaction signature, as felt*
        for i in 0..5 {
            assert_eq!(
                vm.get_maybe(&(transaction2_signature_ptr + i as usize).unwrap()),
                Some(keth_block.transactions[0].signature.data[i].0.clone())
            );
        }
        // After the last transaction signature index, the memory should be None.
        assert_eq!(vm.get_maybe(&(transaction2_signature_ptr + 5usize).unwrap()), None);

        // Transaction sender as an address:
        assert_eq!(
            vm.get_maybe(&(transaction_ptr + 9usize).unwrap()),
            Some(keth_block.transactions[1].sender.0.clone())
        );

        // End of the transactions
        assert_eq!(vm.get_maybe(&(transaction_ptr + 10usize).unwrap()), None);
    }

    #[test]
    #[allow(clippy::too_many_lines, clippy::cognitive_complexity, clippy::unnecessary_cast)]
    fn test_arbitrary_arg_block() {
        // Prepare a random byte array for testing
        let raw_bytes = [0u8; 1500];
        let mut unstructured = Unstructured::new(&raw_bytes);

        // Generate an arbitrary `SealedBlock`
        let original_block: SealedBlock = SealedBlock::arbitrary(&mut unstructured)
            .expect("Failed to generate arbitrary SealedBlock");

        // Convert the `SealedBlock` to `KethBlock`
        let keth_block: KethBlock = original_block.into();

        // Transform the KethBlock into a KethPayload
        let keth_payload: KethPayload = keth_block.clone().into();

        // Create a new instance of the VirtualMachine.
        let mut vm = VirtualMachine::new(false);

        // Call gen_arg to encode the block payload and write it to the VM's memory.
        let result = keth_payload.gen_arg(&mut vm);

        // Retrieve the resulting pointer to the memory segment for the complex Nested payload.
        let ptr = match result.expect("Failed to gen_arg the block payload") {
            MaybeRelocatable::RelocatableValue(relocatable) => relocatable,
            MaybeRelocatable::Int(_) => panic!("Expected a valid pointer"),
        };

        // Extract the block header pointer
        let header_ptr = vm.get_maybe(&ptr).unwrap().get_relocatable().unwrap();

        let transaction_ptr =
            vm.get_maybe(&(ptr + 2usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The ommers hash as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 2usize).unwrap()),
            Some(keth_block.block_header.ommers_hash.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 3usize).unwrap()),
            Some(keth_block.block_header.ommers_hash.high.0)
        );

        // The beneficiary as Address with a single Felt
        assert_eq!(
            vm.get_maybe(&(header_ptr + 4usize).unwrap()),
            Some(keth_block.block_header.coinbase.0)
        );

        // The state root as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 5usize).unwrap()),
            Some(keth_block.block_header.state_root.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 6usize).unwrap()),
            Some(keth_block.block_header.state_root.high.0)
        );

        // The transactions root as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 7usize).unwrap()),
            Some(keth_block.block_header.transactions_root.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 8usize).unwrap()),
            Some(keth_block.block_header.transactions_root.high.0)
        );

        // The receipt root as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 9usize).unwrap()),
            Some(keth_block.block_header.receipt_root.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 10usize).unwrap()),
            Some(keth_block.block_header.receipt_root.high.0)
        );

        // The withdrawal root as an Option of U256*:
        // - is_some
        // - address of the U256
        assert_eq!(
            vm.get_maybe(&(header_ptr + 11usize).unwrap()),
            Some(keth_block.block_header.withdrawals_root.is_some.0)
        );

        let withdrawal_root_ptr =
            vm.get_maybe(&(header_ptr + 12usize).unwrap()).unwrap().get_relocatable().unwrap();

        // Withdrawal root U256 pointer:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&withdrawal_root_ptr),
            // Some(keth_block.block_header.withdrawals_root.value.data[0].0.clone())
            None
        );
        assert_eq!(vm.get_maybe(&(withdrawal_root_ptr + 1usize).unwrap()), None);
        assert_eq!(vm.get_maybe(&(withdrawal_root_ptr + 2usize).unwrap()), None);

        // The bloom as a pointer:
        // - The address at which the data are
        let bloom_ptr =
            vm.get_maybe(&(header_ptr + 13usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The Bloom data, as felt*
        for i in 0..16 {
            assert_eq!(
                vm.get_maybe(&(bloom_ptr + i as usize).unwrap()),
                Some(keth_block.block_header.bloom.data[i].0.clone())
            );
        }
        // After the last Bloom data index, the memory should be None.
        assert_eq!(vm.get_maybe(&(bloom_ptr + 16usize).unwrap()), None);

        // The difficulty as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 14usize).unwrap()),
            Some(keth_block.block_header.difficulty.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 15usize).unwrap()),
            Some(keth_block.block_header.difficulty.high.0)
        );

        // The block number as MaybeRelocatable:
        assert_eq!(
            vm.get_maybe(&(header_ptr + 16usize).unwrap()),
            Some(keth_block.block_header.number.0)
        );

        // The gas limit as MaybeRelocatable:
        assert_eq!(
            vm.get_maybe(&(header_ptr + 17usize).unwrap()),
            Some(keth_block.block_header.gas_limit.0)
        );

        // The gas used as MaybeRelocatable:
        assert_eq!(
            vm.get_maybe(&(header_ptr + 18usize).unwrap()),
            Some(keth_block.block_header.gas_used.0)
        );

        // The timestamp as MaybeRelocatable:
        assert_eq!(
            vm.get_maybe(&(header_ptr + 19usize).unwrap()),
            Some(keth_block.block_header.timestamp.0)
        );

        // The mix hash as U256:
        // - Low
        // - High
        assert_eq!(
            vm.get_maybe(&(header_ptr + 20usize).unwrap()),
            Some(keth_block.block_header.mix_hash.low.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 21usize).unwrap()),
            Some(keth_block.block_header.mix_hash.high.0)
        );

        // The nonce as MaybeRelocatable:
        assert_eq!(
            vm.get_maybe(&(header_ptr + 22usize).unwrap()),
            Some(keth_block.block_header.nonce.0)
        );

        // The base fee per gas as an Option of MaybeRelocatable:
        // - is_some
        // - Value
        assert_eq!(
            vm.get_maybe(&(header_ptr + 23usize).unwrap()),
            Some(keth_block.block_header.base_fee_per_gas.is_some.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 24usize).unwrap()),
            Some(keth_block.block_header.base_fee_per_gas.value.0)
        );

        // The blob gas used as an Option of MaybeRelocatable:
        // - is_some
        // - Value
        assert_eq!(
            vm.get_maybe(&(header_ptr + 25usize).unwrap()),
            Some(keth_block.block_header.blob_gas_used.is_some.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 26usize).unwrap()),
            Some(keth_block.block_header.blob_gas_used.value.0)
        );

        // The excess blob gas as an Option of MaybeRelocatable:
        // - is_some
        // - Value
        assert_eq!(
            vm.get_maybe(&(header_ptr + 27usize).unwrap()),
            Some(keth_block.block_header.excess_blob_gas.is_some.0)
        );
        assert_eq!(
            vm.get_maybe(&(header_ptr + 28usize).unwrap()),
            Some(keth_block.block_header.excess_blob_gas.value.0)
        );

        // The parent beacon block root as an Option of U256*:
        // - is_some
        // - address of the U256
        assert_eq!(
            vm.get_maybe(&(header_ptr + 29usize).unwrap()),
            Some(keth_block.block_header.parent_beacon_block_root.is_some.0)
        );
        let parent_beacon_block_root_ptr =
            vm.get_maybe(&(header_ptr + 30usize).unwrap()).unwrap().get_relocatable().unwrap();

        // Parent Beacon Block Root U256 pointer:
        // - Low
        // - High
        assert_eq!(vm.get_maybe(&parent_beacon_block_root_ptr), None);

        assert_eq!(vm.get_maybe(&(parent_beacon_block_root_ptr + 2usize).unwrap()), None);

        // The requests root as an Option of U256*:
        // - is_some
        // - address of the U256
        assert_eq!(
            vm.get_maybe(&(header_ptr + 31usize).unwrap()),
            Some(keth_block.block_header.requests_root.is_some.0)
        );
        let requests_root_ptr =
            vm.get_maybe(&(header_ptr + 32usize).unwrap()).unwrap().get_relocatable().unwrap();

        // Requests Root U256 pointer (None in this case):
        // - Low
        // - High
        assert_eq!(vm.get_maybe(&requests_root_ptr), None);

        // The extra data pointer as KethPointer:
        // - Length
        // - Address
        assert_eq!(
            vm.get_maybe(&(header_ptr + 33usize).unwrap()),
            Some(keth_block.block_header.extra_data.len.unwrap().0)
        );
        let extra_data_ptr =
            vm.get_maybe(&(header_ptr + 34usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The Extra Data, as felt*, should be stored in the second segment of the memory.
        assert_eq!(vm.get_maybe(&extra_data_ptr), None);
        // After the last Extra Data index, the memory should be None.
        assert_eq!(vm.get_maybe(&(extra_data_ptr + 1usize).unwrap()), None);

        // End of the header
        assert_eq!(vm.get_maybe(&(header_ptr + 35usize).unwrap()), None);

        // First transaction
        // Rlp of the transaction as a KethPointer:
        // - Length
        // - Address
        assert_eq!(
            vm.get_maybe(&transaction_ptr),
            Some(keth_block.transactions[0].rlp.len.clone().unwrap().0)
        );
        let transaction1_rlp_ptr =
            vm.get_maybe(&(transaction_ptr + 1usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The first transaction rlp, as felt*
        for i in 0..7 {
            assert_eq!(
                vm.get_maybe(&(transaction1_rlp_ptr + i as usize).unwrap()),
                Some(keth_block.transactions[0].rlp.data[i].0.clone())
            );
        }
        // After the last transaction rlp index, the memory should be None.
        assert_eq!(vm.get_maybe(&(transaction1_rlp_ptr + 128usize).unwrap()), None);

        // Transaction signature as a KethPointer:
        // - Length
        // - Address
        assert_eq!(
            vm.get_maybe(&(transaction_ptr + 2usize).unwrap()),
            Some(keth_block.transactions[0].signature.len.clone().unwrap().0)
        );
        let transaction1_signature_ptr =
            vm.get_maybe(&(transaction_ptr + 3usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The first transaction signature, as felt*
        for i in 0..5 {
            assert_eq!(
                vm.get_maybe(&(transaction1_signature_ptr + i as usize).unwrap()),
                Some(keth_block.transactions[0].signature.data[i].0.clone())
            );
        }
        // After the last transaction signature index, the memory should be None.
        assert_eq!(vm.get_maybe(&(transaction1_signature_ptr + 5usize).unwrap()), None);

        // Transaction sender as an address:
        assert_eq!(
            vm.get_maybe(&(transaction_ptr + 4usize).unwrap()),
            Some(keth_block.transactions[0].sender.0.clone())
        );

        // Second transaction
        // Rlp of the transaction as a KethPointer:
        // - Length
        // - Address
        assert_eq!(
            vm.get_maybe(&(transaction_ptr + 5usize).unwrap()),
            Some(keth_block.transactions[1].rlp.len.clone().unwrap().0)
        );
        let transaction2_rlp_ptr =
            vm.get_maybe(&(transaction_ptr + 6usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The second transaction rlp, as felt*
        for i in 0..7 {
            assert_eq!(
                vm.get_maybe(&(transaction2_rlp_ptr + i as usize).unwrap()),
                Some(keth_block.transactions[0].rlp.data[i].0.clone())
            );
        }
        // After the last transaction rlp index, the memory should be None.
        assert_eq!(vm.get_maybe(&(transaction2_rlp_ptr + 128usize).unwrap()), None);

        // Transaction signature as a KethPointer:
        // - Length
        // - Address
        assert_eq!(
            vm.get_maybe(&(transaction_ptr + 7usize).unwrap()),
            Some(keth_block.transactions[1].signature.len.clone().unwrap().0)
        );
        let transaction2_signature_ptr =
            vm.get_maybe(&(transaction_ptr + 8usize).unwrap()).unwrap().get_relocatable().unwrap();

        // The first transaction signature, as felt*
        for i in 0..5 {
            assert_eq!(
                vm.get_maybe(&(transaction2_signature_ptr + i as usize).unwrap()),
                Some(keth_block.transactions[1].signature.data[i].0.clone())
            );
        }
        // After the last transaction signature index, the memory should be None.
        assert_eq!(vm.get_maybe(&(transaction2_signature_ptr + 5usize).unwrap()), None);

        // Transaction sender as an address:
        assert_eq!(
            vm.get_maybe(&(transaction_ptr + 9usize).unwrap()),
            Some(keth_block.transactions[1].sender.0.clone())
        );

        // End of the transactions
        assert_eq!(
            vm.get_maybe(&(transaction_ptr + 10usize).unwrap()),
            Some(MaybeRelocatable::Int(Felt252::from(7)))
        );
    }
}
