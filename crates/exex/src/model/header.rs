use super::primitives::{
    KethMaybeRelocatable, KethOption, KethPointer, KethSimplePointer, KethU256,
};
use alloy_consensus::Header;
use serde::{Deserialize, Serialize};

/// Represents a Keth block header, which contains essential metadata about a block.
///
/// These data are converted into a Keth-specific format for use with the Cairo VM.
#[derive(Default, Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethBlockHeader {
    /// Hash of the parent block.
    pub parent_hash: KethU256,
    /// Hash of the ommers (uncle blocks) of the block.
    pub ommers_hash: KethU256,
    /// Address of the beneficiary or coinbase address (the miner or validator).
    pub coinbase: KethMaybeRelocatable,
    /// State root, which represents the root hash of the state trie after transactions.
    pub state_root: KethU256,
    /// Root of the trie that contains the block's transactions.
    pub transactions_root: KethU256,
    /// Root of the trie that contains the block's transaction receipts.
    pub receipt_root: KethU256,
    /// Root of the trie that contains withdrawals in the block.
    pub withdrawals_root: KethOption<KethSimplePointer>,
    /// Logs bloom filter for efficient log search.
    pub bloom: KethSimplePointer,
    /// Block difficulty value, which defines how difficult it is to mine the block.
    pub difficulty: KethU256,
    /// Block number, i.e., the height of the block in the chain.
    pub number: KethMaybeRelocatable,
    /// Gas limit for the block, specifying the maximum gas that can be used by transactions.
    pub gas_limit: KethMaybeRelocatable,
    /// Total amount of gas used by transactions in this block.
    pub gas_used: KethMaybeRelocatable,
    /// Timestamp of when the block was mined or validated.
    pub timestamp: KethMaybeRelocatable,
    /// Mix hash used for proof-of-work verification.
    pub mix_hash: KethU256,
    /// Nonce value used for proof-of-work.
    pub nonce: KethMaybeRelocatable,
    /// Base fee per gas (EIP-1559), which represents the minimum gas fee per transaction.
    pub base_fee_per_gas: KethOption<KethMaybeRelocatable>,
    /// Blob gas used in the block.
    pub blob_gas_used: KethOption<KethMaybeRelocatable>,
    /// Excess blob gas for rollups.
    pub excess_blob_gas: KethOption<KethMaybeRelocatable>,
    /// Root of the parent beacon block in the proof-of-stake chain.
    pub parent_beacon_block_root: KethOption<KethSimplePointer>,
    /// Root of the trie containing request receipts.
    pub requests_root: KethOption<KethSimplePointer>,
    /// Extra data provided within the block, usually for protocol-specific purposes.
    pub extra_data: KethPointer,
}

impl From<Header> for KethBlockHeader {
    /// Implements the conversion from a [`Header`] to a [`KethBlockHeader`].
    fn from(value: Header) -> Self {
        Self {
            parent_hash: value.parent_hash.into(),
            ommers_hash: value.ommers_hash.into(),
            coinbase: value.beneficiary.into(),
            state_root: value.state_root.into(),
            transactions_root: value.transactions_root.into(),
            receipt_root: value.receipts_root.into(),
            withdrawals_root: value.withdrawals_root.into(),
            bloom: value.logs_bloom.into(),
            difficulty: value.difficulty.into(),
            number: value.number.into(),
            gas_limit: value.gas_limit.into(),
            gas_used: value.gas_used.into(),
            timestamp: value.timestamp.into(),
            mix_hash: value.mix_hash.into(),
            nonce: value.nonce.into(),
            base_fee_per_gas: value.base_fee_per_gas.into(),
            blob_gas_used: value.blob_gas_used.into(),
            excess_blob_gas: value.excess_blob_gas.into(),
            parent_beacon_block_root: value.parent_beacon_block_root.into(),
            requests_root: value.requests_hash.into(),
            extra_data: value.extra_data.into(),
        }
    }
}

impl KethBlockHeader {
    /// Function used to convert the [`KethBlockHeader`] to a Header in order to build roundtrip
    /// tests.
    #[cfg(test)]
    pub fn to_reth_header(&self) -> Header {
        Header {
            parent_hash: self.parent_hash.to_b256(),
            ommers_hash: self.ommers_hash.to_b256(),
            beneficiary: self.coinbase.to_address(),
            state_root: self.state_root.to_b256(),
            transactions_root: self.transactions_root.to_b256(),
            receipts_root: self.receipt_root.to_b256(),
            withdrawals_root: self.withdrawals_root.to_option_b256(),
            logs_bloom: self.bloom.to_bloom(),
            difficulty: self.difficulty.to_u256(),
            number: self.number.to_u64(),
            gas_limit: self.gas_limit.to_u64(),
            gas_used: self.gas_used.to_u64(),
            timestamp: self.timestamp.to_u64(),
            mix_hash: self.mix_hash.to_b256(),
            nonce: self.nonce.to_u64().into(),
            base_fee_per_gas: self.base_fee_per_gas.to_option_u64(),
            blob_gas_used: self.blob_gas_used.to_option_u64(),
            excess_blob_gas: self.excess_blob_gas.to_option_u64(),
            parent_beacon_block_root: self.parent_beacon_block_root.to_option_b256(),
            requests_hash: self.requests_root.to_option_b256(),
            extra_data: self.extra_data.to_bytes(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use arbitrary::{Arbitrary, Unstructured};
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn test_header_arbitrary_roundtrip_conversion(raw_bytes in any::<[u8; 1000]>()) {
            let mut unstructured = Unstructured::new(&raw_bytes);

            // Generate an arbitrary Header using Arbitrary
            let original_header = Header::arbitrary(&mut unstructured).expect("Failed to generate arbitrary Header");

            // Convert the arbitrary Header into KethBlockHeader
            let keth_header: KethBlockHeader = original_header.clone().into();

            // Convert it back to a Header
            let final_header: Header = keth_header.to_reth_header();

            // Assert that the original Header and the final one after roundtrip are equal
            prop_assert_eq!(final_header, original_header);
        }
    }
}
