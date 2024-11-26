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
    /// - `len`: The length of the data segment.
    /// - `data`: The data itself, encoded as another [`KethPayload`].
    Pointer {
        /// The length of the pointer data.
        len: MaybeRelocatable,
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
    fn collect_args(&self, vm: &mut VirtualMachine) -> Result<Vec<MaybeRelocatable>, MemoryError> {
        match self {
            Self::Flat(values) => Ok(values.clone()),
            Self::Option { is_some, value } => {
                let mut args = vec![is_some.clone()];
                args.extend(value.collect_args(vm)?);
                Ok(args)
            }
            Self::Pointer { len, data } => Ok(vec![len.clone(), data.gen_arg(vm)?]),
            Self::Nested(values) => {
                let mut args = Vec::new();
                for value in values {
                    args.extend(value.collect_args(vm)?);
                }
                Ok(args)
            }
        }
    }

    pub fn gen_arg(&self, vm: &mut VirtualMachine) -> Result<MaybeRelocatable, MemoryError> {
        let args = self.collect_args(vm)?;
        vm.gen_arg(&args)
    }
}

impl From<KethBlockHeader> for KethPayload {
    fn from(header: KethBlockHeader) -> Self {
        let mut payload = Vec::new();

        // Dynamically encode each field using a trait
        let fields = [
            &header.parent_hash as &dyn KethEncodable,
            &header.ommers_hash,
            &header.coinbase,
            &header.state_root,
            &header.transactions_root,
            &header.receipt_root,
            &header.withdrawals_root,
            &header.bloom,
            &header.difficulty,
            &header.number,
            &header.gas_limit,
            &header.gas_used,
            &header.timestamp,
            &header.mix_hash,
            &header.nonce,
            &header.base_fee_per_gas,
            &header.blob_gas_used,
            &header.excess_blob_gas,
            &header.parent_beacon_block_root,
            &header.requests_root,
            &header.extra_data,
        ];

        for field in fields {
            payload.push(field.encode());
        }

        Self::Nested(payload)
    }
}

impl From<KethTransactionEncoded> for KethPayload {
    fn from(transaction: KethTransactionEncoded) -> Self {
        let mut payload = Vec::new();

        // Dynamically encode each field using a trait
        let fields =
            [&transaction.rlp as &dyn KethEncodable, &transaction.signature, &transaction.sender];

        for field in fields {
            payload.push(field.encode());
        }

        Self::Nested(payload)
    }
}

impl From<KethBlock> for KethPayload {
    fn from(block: KethBlock) -> Self {
        let mut payload = Vec::new();

        // Encode the block header
        payload.push(block.block_header.into());

        // Encode the transaction count
        payload.push(block.transactions_len.encode());

        // Encode the transactions
        let transactions_payload = block.transactions.into_iter().map(Into::into).collect();

        payload.push(Self::Nested(transactions_payload));

        Self::Nested(payload)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::primitives::{KethMaybeRelocatable, KethOption, KethPointer, KethU256};
    use alloy_consensus::Header;
    use alloy_primitives::{Address, Bloom, Bytes, B256, U256};
    use arbitrary::{Arbitrary, Unstructured};
    use cairo_vm::types::relocatable::Relocatable;
    use reth_primitives::{SealedBlock, TransactionSigned};

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
        if let KethPayload::Nested(fields) = payload {
            // Verify each field individually by reconstructing the expected payloads
            let expected_fields = vec![
                KethU256::from(parent_hash).encode(),
                KethU256::from(ommers_hash).encode(),
                KethMaybeRelocatable::from(coinbase).encode(),
                KethU256::from(state_root).encode(),
                KethU256::from(transactions_root).encode(),
                KethU256::from(receipt_root).encode(),
                KethOption::<KethU256>::from(withdrawals_root).encode(),
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
                KethOption::<KethU256>::from(parent_beacon_block_root).encode(),
                KethOption::<KethU256>::from(requests_root).encode(),
                KethPointer::from(extra_data).encode(),
            ];

            assert_eq!(fields.len(), expected_fields.len(), "Field count mismatch in payload");

            for (actual, expected) in fields.iter().zip(expected_fields.iter()) {
                assert_eq!(actual, expected, "Field mismatch in payload");
            }
        } else {
            panic!("Expected payload to be of type Nested");
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
            if let KethPayload::Nested(transaction_fields) = &fields[2] {
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
                panic!("Expected Nested payload for transactions");
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
            len: MaybeRelocatable::from(3),
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
                len: MaybeRelocatable::from(3),
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
}
