use super::{
    header::KethBlockHeader, primitives::KethMaybeRelocatable, transaction::KethTransactionEncoded,
};
use reth_primitives::SealedBlock;
use serde::{Deserialize, Serialize};

/// Represents a Keth block, containing metadata about the block and its transactions.
///
/// This structure is a specialized format designed for use in the Cairo VM or other
/// environments requiring Keth-specific encodings.
///
/// It is derived from the [`SealedBlock`] structure and provides necessary information about the
/// block header and its transactions.
#[derive(Default, Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethBlock {
    /// The block header encapsulated in the [`KethBlockHeader`] structure.
    pub block_header: KethBlockHeader,

    /// The number of transactions in the block.
    pub transactions_len: KethMaybeRelocatable,

    /// The list of transactions included in the block.
    pub transactions: Vec<KethTransactionEncoded>,
}

impl From<SealedBlock> for KethBlock {
    fn from(value: SealedBlock) -> Self {
        Self {
            block_header: value.header().clone().into(),
            transactions_len: value.body.transactions.len().into(),
            transactions: value
                .body
                .transactions
                .into_iter()
                .map(|tx| tx.try_into_ecrecovered().expect("failed to recover signer").into())
                .collect(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use arbitrary::{Arbitrary, Unstructured};
    use reth_primitives::SealedHeader;

    impl KethBlock {
        /// Converts a [`KethBlock`] to a [`SealedHeader`] for round-trip testing.
        fn sealed_header(&self) -> SealedHeader {
            let header = self.block_header.to_reth_header();
            let hash = header.hash_slow();
            SealedHeader::new(header, hash)
        }
    }

    #[test]
    fn test_block_arbitrary_roundtrip_conversion() {
        // Prepare a random byte array for testing
        let raw_bytes = [0u8; 1500];
        let mut unstructured = Unstructured::new(&raw_bytes);

        // Generate an arbitrary `SealedBlock`
        let original_block: SealedBlock = SealedBlock::arbitrary(&mut unstructured)
            .expect("Failed to generate arbitrary SealedBlock");

        // Convert the `SealedBlock` to `KethBlock`
        let keth_block: KethBlock = original_block.clone().into();

        // Convert the `KethBlock` back to `SealedHeader`
        let sealed_header = keth_block.sealed_header();

        // Assert that the `SealedHeader` matches the original block's header
        assert_eq!(sealed_header, original_block.header);

        // Assert that the `KethBlock` has the same number of transactions as the original block
        assert_eq!(
            keth_block.transactions_len.to_u64() as usize,
            original_block.body.transactions.len()
        );
        assert_eq!(keth_block.transactions_len.to_u64() as usize, keth_block.transactions.len());

        for (keth_tx, original_tx) in
            keth_block.transactions.iter().zip(original_block.body.transactions.iter())
        {
            // Encode the original transaction via RLP for comparison
            let mut buffer = Vec::new();
            original_tx.transaction.encode_for_signing(&mut buffer);

            // Get the encoded bytes from the Keth pointer
            let encoded_bytes = keth_tx.rlp.to_transaction_rlp();

            // Assert that the encoded bytes match
            assert_eq!(encoded_bytes, buffer.clone());

            // Assert that the buffer length matches the length in the Keth RLP structure
            assert_eq!(
                buffer.len(),
                usize::try_from(keth_tx.rlp.len.to_u64()).expect("Invalid length conversion")
            );

            // Assert that the type size is 1
            assert_eq!(keth_tx.rlp.type_size, 1);

            // Verify the signature matches
            assert_eq!(keth_tx.signature.to_signature(), original_tx.signature);

            // Verify the sender matches
            assert_eq!(
                keth_tx.sender.to_address(),
                original_tx.recover_signer().expect("Failed to recover signer")
            );
        }
    }
}
