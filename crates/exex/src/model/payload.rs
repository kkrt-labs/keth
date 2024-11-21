use super::header::KethBlockHeader;
use cairo_vm::types::relocatable::MaybeRelocatable;
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::models::primitives::{KethMaybeRelocatable, KethOption, KethPointer, KethU256};
    use alloy_consensus::Header;
    use alloy_primitives::{Address, Bloom, Bytes, B256, U256};

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
}
