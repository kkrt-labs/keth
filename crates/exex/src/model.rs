use alloy_consensus::Header;
use alloy_primitives::{Address, Bloom, Bytes, B256, B64, U256};
use alloy_rlp::Encodable;
use cairo_vm::{types::relocatable::MaybeRelocatable, Felt252};
use reth_primitives::{Signature, Transaction, TransactionSigned, TransactionSignedEcRecovered};
use serde::{Deserialize, Serialize};
use thiserror::Error;

/// The size in bytes of the `u128` type.
pub const U128_BYTES_SIZE: usize = std::mem::size_of::<u128>();

/// This represents the possible errors that can occur during conversions from Ethereum format to
/// CairoVM compatible formats.
#[derive(Error, Debug)]
pub enum ConversionError {
    /// Error indicating the failure to recover the signer from the transaction.
    #[error("Failed to recover signer from transaction")]
    TransactionSigner,
}

/// A custom wrapper around [`MaybeRelocatable`] for the Keth execution environment.
///
/// This struct serves as a utility for wrapping [`MaybeRelocatable`] values in Keth, which uses
/// [`Felt252`] as the core type to represent numerical values within its system.
///
/// Additionally, this wrapper facilitates operations such as conversions between different Keth
/// types, making it easier to work with the underlying data structures.
///
/// # Usage
/// - This type is primarily used for wrapping values in Keth, enabling smooth interoperation
///   between [`Felt252`], [`MaybeRelocatable`] and reth primitive data.
#[derive(Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethMaybeRelocatable(MaybeRelocatable);

impl Default for KethMaybeRelocatable {
    fn default() -> Self {
        Self::zero()
    }
}

impl KethMaybeRelocatable {
    /// Creates a [`KethMaybeRelocatable`] instance representing the value `0`.
    ///
    /// This method wraps [`Felt252::ZERO`] in the [`MaybeRelocatable`] type and
    /// provides a convenient way to represent zero in computations or storage.
    ///
    /// # Examples
    ///
    /// ```
    /// use kakarot_exex::model::KethMaybeRelocatable;
    ///
    /// let zero_value = KethMaybeRelocatable::zero();
    /// ```
    pub fn zero() -> Self {
        Self(Felt252::ZERO.into())
    }

    /// Creates a [`KethMaybeRelocatable`] instance representing the value `1`.
    ///
    /// This method wraps [`Felt252::ONE`] in the [`MaybeRelocatable`] type and
    /// provides a convenient way to represent one in computations or storage.
    ///
    /// # Examples
    ///
    /// ```
    /// use kakarot_exex::model::KethMaybeRelocatable;
    ///
    /// let one_value = KethMaybeRelocatable::one();
    /// ```
    pub fn one() -> Self {
        Self(Felt252::ONE.into())
    }

    /// Creates a [`KethMaybeRelocatable`] instance from a byte slice in big-endian order.
    ///
    /// This method takes a byte slice and converts it into a [`KethMaybeRelocatable`]
    /// by interpreting the bytes as a [`Felt252`] value in big-endian format.
    ///
    /// # Parameters
    ///
    /// - `bytes`: A slice of bytes that represents a big-endian encoded value.
    ///
    /// # Returns
    ///
    /// Returns an instance of [`KethMaybeRelocatable`] that corresponds to the given byte slice.
    ///
    /// # Examples
    ///
    /// ```
    /// use kakarot_exex::model::KethMaybeRelocatable;
    ///
    /// let bytes: &[u8] = &[0x00, 0x01, 0x02, 0x03]; // Example big-endian byte array
    /// let keth_value = KethMaybeRelocatable::from_bytes_be_slice(bytes);
    /// ```
    pub fn from_bytes_be_slice(bytes: &[u8]) -> Self {
        Felt252::from_bytes_be_slice(bytes).into()
    }
}

impl From<Felt252> for KethMaybeRelocatable {
    fn from(value: Felt252) -> Self {
        Self(value.into())
    }
}

impl From<u8> for KethMaybeRelocatable {
    fn from(value: u8) -> Self {
        Self(Felt252::from(value).into())
    }
}

impl From<u64> for KethMaybeRelocatable {
    fn from(value: u64) -> Self {
        Self(Felt252::from(value).into())
    }
}

impl From<B64> for KethMaybeRelocatable {
    fn from(value: B64) -> Self {
        Into::<u64>::into(value).into()
    }
}

impl From<usize> for KethMaybeRelocatable {
    fn from(value: usize) -> Self {
        Self(Felt252::from(value).into())
    }
}

impl From<Address> for KethMaybeRelocatable {
    fn from(value: Address) -> Self {
        Self::from_bytes_be_slice(&value.0 .0)
    }
}

/// [`KethOption`] is a custom representation of a Rust [`Option<T>`] type where `T` can be
/// any type, such as [`KethMaybeRelocatable`] or [`KethU256`].
///
/// This is specifically tailored for use within the Keth model inside our OS.
///
/// This struct encapsulates two fields:
/// - `is_some`: A flag that indicates whether the option contains a value (`is_some = 1`) or is
///   empty (`is_some = 0`).
/// - `value`: The actual value of the option, which can be of any type `T`.
///
/// When the option is [`None`], the `value` field is assigned a default value. This struct
/// provides a way to handle optional values in a manner consistent with the Keth model's memory
/// representation.
#[derive(Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethOption<T> {
    /// Indicates whether the option contains a value ([`Some`]) or is empty ([`None`]).
    /// - When set to `1`, it indicates the presence of a value.
    /// - When set to `0`, it represents a [`None`] value.
    is_some: KethMaybeRelocatable,

    /// The value stored in the option, which can be of type `T`.
    ///
    /// If the option is [`None`], this field holds a default value.
    value: T,
}

impl Default for KethOption<KethMaybeRelocatable> {
    fn default() -> Self {
        Self { is_some: KethMaybeRelocatable::zero(), value: KethMaybeRelocatable::zero() }
    }
}

impl Default for KethOption<KethU256> {
    fn default() -> Self {
        Self { is_some: KethMaybeRelocatable::zero(), value: KethU256::zero() }
    }
}

impl<U, T> From<Option<T>> for KethOption<U>
where
    T: Into<U>,
    KethOption<U>: Default,
{
    fn from(value: Option<T>) -> Self {
        match value {
            Some(value) => KethOption { is_some: KethMaybeRelocatable::one(), value: value.into() },
            None => KethOption::default(),
        }
    }
}

/// [`KethU256`] represents a 256-bit unsigned integer used within the Keth model.
///
/// This struct is designed to encapsulate two components of a 256-bit number:
/// - `low`: Represents the lower 128 bits of the 256-bit integer, stored as a
///   [`KethMaybeRelocatable`] type.
/// - `high`: Represents the upper 128 bits of the 256-bit integer, also stored as a
///   [`KethMaybeRelocatable`].
#[derive(Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethU256 {
    /// The lower 128 bits of the 256-bit unsigned integer.
    ///
    /// This field is represented as a [`KethMaybeRelocatable`] type.
    low: KethMaybeRelocatable,

    /// The upper 128 bits of the 256-bit unsigned integer.
    ///
    /// Like the `low` field, this is stored as a [`KethMaybeRelocatable`].
    high: KethMaybeRelocatable,
}

impl Default for KethU256 {
    fn default() -> Self {
        Self::zero()
    }
}

impl KethU256 {
    pub fn zero() -> Self {
        Self { low: KethMaybeRelocatable::zero(), high: KethMaybeRelocatable::zero() }
    }
}

impl From<B256> for KethU256 {
    fn from(value: B256) -> Self {
        Self {
            low: KethMaybeRelocatable::from_bytes_be_slice(&value.0[U128_BYTES_SIZE..]),
            high: KethMaybeRelocatable::from_bytes_be_slice(&value.0[0..U128_BYTES_SIZE]),
        }
    }
}

impl From<U256> for KethU256 {
    fn from(value: U256) -> Self {
        Self {
            low: KethMaybeRelocatable::from_bytes_be_slice(
                &value.to_be_bytes::<{ U256::BYTES }>()[U128_BYTES_SIZE..],
            ),
            high: KethMaybeRelocatable::from_bytes_be_slice(
                &value.to_be_bytes::<{ U256::BYTES }>()[0..U128_BYTES_SIZE],
            ),
        }
    }
}

/// [`KethPointer`] holds a length field and a vector of [`KethU256`] values to represent complex
/// data.
///
/// This struct is used to represent complex data structures such as Bloom filters or Bytes data in
/// a format that can be stored and processed by the CairoVM.
///
/// It efficiently stores 256-bit values and provides an interface for converting data structures
/// into a compatible format.
#[derive(Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethPointer {
    /// The length of the data to be stored.
    len: KethMaybeRelocatable,

    /// A vector holding the main data, represented as [`KethU256`] values.
    data: Vec<KethMaybeRelocatable>,

    /// The size of the underlying Cairo struct (see `.SIZE`)
    ///
    /// By default, this is set to 1, which is the size of a single felt in Cairo.
    type_size: usize,
}

impl Default for KethPointer {
    fn default() -> Self {
        Self { len: KethMaybeRelocatable::zero(), data: Vec::new(), type_size: 1 }
    }
}

impl From<Bloom> for KethPointer {
    /// Converts a [`Bloom`] filter into a [`KethPointer`] structure.
    ///
    /// The [`Bloom`] filter is represented as a 256-byte array in big-endian order. Since
    /// CairoVM's [`Felt252`] can only handle values up to 252 bits, we need to break the
    /// 256-byte array into smaller chunks that fit within this limit.
    ///
    /// The conversion process works as follows:
    /// - The first field (`len`) holds the length of the original data, represented as a
    ///   [`KethMaybeRelocatable`].
    /// - The `data` field stores the remaining elements as chunks of [`U128_BYTES_SIZE`] bytes each
    ///   from the Bloom filter, with each chunk converted into a [`KethMaybeRelocatable`].
    ///
    /// This process allows the 256-byte Bloom filter to be stored and processed efficiently in the
    /// `KethPointer` structure, making it compatible with CairoVM's constraints.
    fn from(value: Bloom) -> Self {
        Self {
            // The length of the Bloom filter.
            len: value.len().into(),
            // Chunk the 256-byte array into groups of 16 bytes and convert.
            data: value
                .0
                .chunks(U128_BYTES_SIZE)
                .map(KethMaybeRelocatable::from_bytes_be_slice)
                .collect(),
            // In Cairo, Bloom is a pointer to a segment of felts.
            type_size: 1,
        }
    }
}

impl From<Bytes> for KethPointer {
    /// Converts a [`Bytes`] object into a [`KethPointer`] structure.
    ///
    /// This method takes a [`Bytes`] object (which represents a sequence of bytes) and
    /// converts it into the [`KethPointer`] format, making it compatible with CairoVM's
    /// 252-bit limitation for [`Felt252`] values.
    ///
    /// The conversion process:
    /// - The `len` field represents the total length of the input bytes, converted into a
    ///   [`KethMaybeRelocatable`] value.
    /// - The `data` field maps each byte of the input to a [`KethMaybeRelocatable`] value
    ///   (represented as a [`Felt252`] in CairoVM). This approach ensures that each byte is
    ///   individually processed and stored as a relocatable field.
    ///
    /// In the Cairo VM a Byte is represented by a felt pointer, this means one byte is one felt.
    /// This is the reason why we convert each byte to a felt without any chunk.
    ///
    /// # Example
    ///
    /// ```rust
    /// use alloy_primitives::Bytes;
    /// use kakarot_exex::model::KethPointer;
    ///
    /// let bytes = Bytes::from(vec![0x01, 0x02, 0x03]);
    /// let keth_pointer = KethPointer::from(bytes);
    /// ```
    fn from(value: Bytes) -> Self {
        Self {
            // The length of the input data.
            len: value.len().into(),
            // Convert each byte to a Felt.
            data: value.0.iter().map(|byte| (*byte).into()).collect(),
            // In Cairo, Bytes is a pointer to a segment of felts.
            type_size: 1,
        }
    }
}

impl From<Signature> for KethPointer {
    /// Converts a [`Signature`] into a [`KethPointer`].
    ///
    /// This implementation encodes an Ethereum-like [`Signature`] into a format compatible with the
    /// Cairo virtual machine by converting the signature's components (R, S, V) into felts.
    ///
    /// Cairo's VM assumes that a [`Signature`] is a pointer to a segment of felts. This
    /// implementation adapts the Ethereum [`Signature`] by splitting its components (R, S, and V)
    /// into parts, each of which is mapped to felts. Specifically:
    ///
    /// - R and S, which are 256-bit integers, are split into their low and high 128-bit parts.
    /// - V, which is typically a single byte, is converted directly into a felt.
    ///
    /// # Fields:
    ///
    /// - `len`: Represents the total length of the signature's components in felts. Here, the
    ///   signature is stored as 5 felts:
    ///   - R: low and high parts (2 felts)
    ///   - S: low and high parts (2 felts)
    ///   - V: single felt
    ///
    /// - `data`: A vector of felts representing the signature. The R and S components are split
    ///   into two 128-bit values (low and high parts), and V is converted directly into a felt.
    ///   This vector is used by the Cairo VM to reference the signature.
    ///
    /// - `type_size`: This is set to `1`, indicating that the pointer refers to a single segment of
    ///   felts within Cairo.
    fn from(value: Signature) -> Self {
        // Convert the signature into multiple felts.
        let r: KethU256 = value.r().into();
        let s: KethU256 = value.s().into();
        let v: KethMaybeRelocatable = value.v().to_u64().into();

        Self {
            // We store the signature as a vector of 5 Felts:
            // - R: low and high parts
            // - S: low and high parts
            // - V: single felt
            len: 5usize.into(),
            // Convert each part of the signature to a felt.
            data: vec![r.low, r.high, s.low, s.high, v],
            // Set the type size to 1, as Cairo expects a signature to be a pointer to a segment of
            // felts.
            type_size: 1,
        }
    }
}

impl From<Transaction> for KethPointer {
    /// Converts a [`Transaction`] into a [`KethPointer`].
    ///
    /// This implementation encodes a given Ethereum [`Transaction`] into RLP format and stores it
    /// as a [`KethPointer`], which is designed for compatibility with the Cairo virtual machine.
    ///
    /// The Cairo VM assumes that a [`Transaction`] is a pointer to a segment of felts, and this
    /// conversion translates the RLP-encoded byte array of the transaction into a list of felts,
    /// which can be used in Cairo.
    ///
    /// # Fields:
    ///
    /// - `len`: Represents the total number of bytes in the RLP-encoded transaction. This is
    ///   important for Cairo to know how many felts to expect when interpreting the transaction.
    ///
    /// - `data`: A vector of felts representing the RLP-encoded byte array of the transaction. Each
    ///   byte of the RLP-encoded transaction is converted into a felt for use in Cairo.
    ///
    /// - `type_size`: Set to `1`, indicating that this represents a single segment of felts in the
    ///   Cairo VM.
    fn from(value: Transaction) -> Self {
        // Initialize an empty buffer to hold the RLP-encoded transaction.
        let mut buffer = Vec::new();
        // Encode the transaction into the buffer using RLP encoding.
        value.encode(&mut buffer);

        Self {
            // Set the `len` field to the length of the encoded byte array.
            // This indicates the size of the transaction in bytes.
            len: buffer.len().into(),
            // Convert the byte array into a vector of felts (one felt per byte).
            // Each byte is mapped into a felt to be used in the Cairo VM.
            data: buffer.into_iter().map(|byte| byte.into()).collect(),
            // Set the type size to `1`, meaning this is a single segment in Cairo.
            type_size: 1,
        }
    }
}

/// Represents a Keth block header, which contains essential metadata about a block.
///
/// These data are converted into a Keth-specific format for use with the CairoVM.
#[derive(Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethBlockHeader {
    /// Hash of the parent block.
    parent_hash: KethU256,
    /// Hash of the ommers (uncle blocks) of the block.
    ommers_hash: KethU256,
    /// Address of the beneficiary or coinbase address (the miner or validator).
    coinbase: KethMaybeRelocatable,
    /// State root, which represents the root hash of the state trie after transactions.
    state_root: KethU256,
    /// Root of the trie that contains the block's transactions.
    transactions_root: KethU256,
    /// Root of the trie that contains the block's transaction receipts.
    receipt_root: KethU256,
    /// Root of the trie that contains withdrawals in the block.
    withdrawals_root: KethOption<KethU256>,
    /// Logs bloom filter for efficient log search.
    bloom: KethPointer,
    /// Block difficulty value, which defines how difficult it is to mine the block.
    difficulty: KethU256,
    /// Block number, i.e., the height of the block in the chain.
    number: KethMaybeRelocatable,
    /// Gas limit for the block, specifying the maximum gas that can be used by transactions.
    gas_limit: KethMaybeRelocatable,
    /// Total amount of gas used by transactions in this block.
    gas_used: KethMaybeRelocatable,
    /// Timestamp of when the block was mined or validated.
    timestamp: KethMaybeRelocatable,
    /// Mix hash used for proof-of-work verification.
    mix_hash: KethU256,
    /// Nonce value used for proof-of-work.
    nonce: KethMaybeRelocatable,
    /// Base fee per gas (EIP-1559), which represents the minimum gas fee per transaction.
    base_fee_per_gas: KethOption<KethMaybeRelocatable>,
    /// Blob gas used in the block.
    blob_gas_used: KethOption<KethMaybeRelocatable>,
    /// Excess blob gas for rollups.
    excess_blob_gas: KethOption<KethMaybeRelocatable>,
    /// Root of the parent beacon block in the proof-of-stake chain.
    parent_beacon_block_root: KethOption<KethU256>,
    /// Root of the trie containing request receipts.
    requests_root: KethOption<KethU256>,
    /// Extra data provided within the block, usually for protocol-specific purposes.
    extra_data: KethPointer,
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
            requests_root: value.requests_root.into(),
            extra_data: value.extra_data.into(),
        }
    }
}

/// [`KethTransactionEncoded`] represents an encoded Ethereum transaction.
///
/// This struct holds three components of a transaction:
/// - The RLP (Recursive Length Prefix) encoding of the transaction.
/// - The signature of the transaction.
/// - The address of the sender.
#[derive(Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethTransactionEncoded {
    /// The RLP encoding of the transaction.
    rlp: KethPointer,

    /// The signature associated with the transaction.
    signature: KethPointer,

    /// The address of the sender.
    sender: KethMaybeRelocatable,
}

impl TryFrom<TransactionSigned> for KethTransactionEncoded {
    type Error = ConversionError;

    /// Attempts to convert a [`TransactionSigned`] into a [`KethTransactionEncoded`].
    fn try_from(value: TransactionSigned) -> Result<Self, Self::Error> {
        // Recover the signer (sender) from the signed transaction.
        // This can fail for some early ethereum mainnet transactions pre EIP-2
        // If it fails, return a `ConversionError` error.
        let sender = value.recover_signer().ok_or(ConversionError::TransactionSigner)?.into();

        // Convert the transaction and its signature to the corresponding types,
        // and return a new `KethTransactionEncoded` instance.
        Ok(Self {
            // The transaction is converted into a `KethPointer` via RLP encoding.
            rlp: value.transaction.into(),
            // The signature is converted into a `KethPointer`.
            signature: value.signature.into(),
            // The sender address is stored as a `KethMaybeRelocatable`.
            sender,
        })
    }
}

impl From<TransactionSignedEcRecovered> for KethTransactionEncoded {
    /// Converts a [`TransactionSignedEcRecovered`] into a [`KethTransactionEncoded`].
    fn from(value: TransactionSignedEcRecovered) -> Self {
        Self {
            // The transaction is converted into a `KethPointer` via RLP encoding.
            rlp: value.transaction.clone().into(),
            // The signature is converted into a `KethPointer`.
            signature: value.signature.into(),
            // The signer is part of the transaction so that we are sure it is correct.
            sender: value.signer().into(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use arbitrary::{Arbitrary, Unstructured};
    use proptest::prelude::*;

    impl KethOption<KethMaybeRelocatable> {
        /// Helper function to convert KethOption to Option<u64>
        fn to_option_u64(&self) -> Option<u64> {
            if self.is_some.0 == MaybeRelocatable::from(Felt252::ONE) {
                // Convert value back to u64 if present
                match &self.value.0 {
                    MaybeRelocatable::Int(felt) => Some(felt.to_string().parse::<u64>().unwrap()),
                    _ => None, // Should never happen
                }
            } else {
                None
            }
        }
    }

    impl KethOption<KethU256> {
        /// Helper function to convert KethOption to Option<B256>
        fn to_option_b256(&self) -> Option<B256> {
            if self.is_some.0 == MaybeRelocatable::from(Felt252::ONE) {
                // Convert value back to B256 if present
                Some(self.value.to_b256())
            } else {
                None
            }
        }
    }

    impl KethU256 {
        /// Convert KethU256 back to B256.
        fn to_b256(&self) -> B256 {
            let high_bytes = self.high.0.get_int().unwrap().to_bytes_be();
            let low_bytes = self.low.0.get_int().unwrap().to_bytes_be();
            let bytes = [
                &high_bytes[U128_BYTES_SIZE..], // Get the high 16 bytes
                &low_bytes[U128_BYTES_SIZE..],  // Get the low 16 bytes
            ]
            .concat();
            B256::from_slice(&bytes)
        }

        /// Convert KethU256 back to U256.
        fn to_u256(&self) -> U256 {
            let high_bytes = self.high.0.get_int().unwrap().to_bytes_be();
            let low_bytes = self.low.0.get_int().unwrap().to_bytes_be();
            let bytes = [
                &high_bytes[U128_BYTES_SIZE..], // Get the high 16 bytes
                &low_bytes[U128_BYTES_SIZE..],  // Get the low 16 bytes
            ]
            .concat();
            U256::from_be_slice(&bytes)
        }
    }

    impl KethMaybeRelocatable {
        fn to_u64(&self) -> u64 {
            self.0.get_int().unwrap().to_string().parse::<u64>().unwrap()
        }

        fn to_address(&self) -> Address {
            // Get the bytes in big-endian order
            let bytes = self.0.get_int().unwrap().to_bytes_be();
            // Extract the last 20 bytes to get the address
            Address::from_slice(&bytes[bytes.len() - Address::len_bytes()..])
        }
    }

    impl KethPointer {
        /// Converts the [`KethPointer`] data into a [`Bytes`] object.
        ///
        /// This function iterates over the `data` field and retrieves the last byte of each.
        ///
        /// # Returns
        /// A [`Bytes`] object containing the last byte of each integer in the `data` field.
        fn to_bytes(&self) -> Bytes {
            Bytes::from(
                self.data
                    // Iterate through the items in the `data` field.
                    .iter()
                    // For each item, retrieve its integer value and convert to big-endian bytes.
                    .flat_map(|item| {
                        // Take only the last byte from the big-endian byte array.
                        //
                        // In Cairo, a byte is represented as a single felt (1 byte = 1 felt).
                        item.0.get_int().unwrap().to_bytes_be().last().copied()
                    })
                    .collect::<Vec<_>>(),
            )
        }

        /// Converts the [`KethPointer`] data into a [`Bloom`] object.
        ///
        /// This function iterates over the `data` field and retrieves the last 16 bytes of each to
        /// form a Bloom filter.
        ///
        /// # Returns
        /// A [`Bloom`] object created from the sliced bytes of the `data` field.
        fn to_bloom(&self) -> Bloom {
            Bloom::from_slice(
                &self
                    .data
                    // Iterate through the items in the `data` field.
                    .iter()
                    // For each item, retrieve its integer value and convert to big-endian bytes.
                    .flat_map(|item| {
                        // Slice the big-endian byte array, taking all bytes after the first 16
                        // (u128 byte size in memory).
                        item.0.get_int().unwrap().to_bytes_be()[U128_BYTES_SIZE..].to_vec()
                    })
                    .collect::<Vec<_>>(),
            )
        }

        /// Converts the [`KethPointer`] data into a [`Signature`] object.
        fn to_signature(&self) -> Signature {
            let r = KethU256 { low: self.data[0].clone(), high: self.data[1].clone() }.to_u256();
            let s = KethU256 { low: self.data[2].clone(), high: self.data[3].clone() }.to_u256();
            let v = self.data[4].clone().to_u64();

            Signature::from_rs_and_parity(r, s, v).expect("Failed to create signature")
        }

        /// Util to convert the KethPointer to RLP encoded transaction bytes.
        fn to_transaction_rlp(&self) -> Vec<u8> {
            // Extract the bytes from the data field
            self.data
                .iter()
                .map(|item| item.0.get_int().unwrap().to_string().parse::<u8>().unwrap())
                .collect::<Vec<_>>()
        }
    }

    impl KethBlockHeader {
        /// Function used to convert the [`KethBlockHeader`] to a Header in order to build roundtrip
        /// tests.
        fn to_reth_header(&self) -> Header {
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
                requests_root: self.requests_root.to_option_b256(),
                extra_data: self.extra_data.to_bytes(),
            }
        }
    }

    proptest! {
        #[test]
        fn test_option_u64_to_keth_option_roundtrip(opt_value in proptest::option::of(any::<u64>())) {
            // Convert Option<u64> to KethOption
            let keth_option = KethOption::from(opt_value);

            // Convert back to Option<u64>
            let roundtrip_value = keth_option.to_option_u64();

            // Assert roundtrip conversion is equal to original value
            prop_assert_eq!(roundtrip_value, opt_value);
        }

        #[test]
        fn test_b256_to_keth_u256_roundtrip(b256_value in any::<B256>()) {
            // Convert B256 to KethU256
            let keth_u256 = KethU256::from(b256_value);

            // Convert back to B256
            let roundtrip_value = keth_u256.to_b256();

            // Assert roundtrip conversion is equal to original value
            prop_assert_eq!(roundtrip_value, b256_value);
        }

        #[test]
        fn test_option_b256_to_keth_option_roundtrip(opt_value in proptest::option::of(any::<B256>())) {
            // Convert Option<B256> to KethOption
            let keth_option = KethOption::from(opt_value);

            // Convert back to Option<B256>
            let roundtrip_value = keth_option.to_option_b256();

            // Assert roundtrip conversion is equal to original value
            prop_assert_eq!(roundtrip_value, opt_value);
        }

        #[test]
        fn test_u256_to_keth_u256_roundtrip(u256_value in any::<U256>()) {
            // Convert U256 to KethU256
            let keth_u256 = KethU256::from(u256_value);

            // Convert back to U256
            let roundtrip_value = keth_u256.to_u256();

            // Assert roundtrip conversion is equal to original value
            prop_assert_eq!(roundtrip_value, u256_value);
        }

        #[test]
        fn test_address_to_keth_maybe_relocatable_roundtrip(address_bytes in any::<[u8; 20]>()) {
            // Create a random address
            let address = Address::new(address_bytes);

            // Convert to KethMaybeRelocatable
            let keth_maybe_relocatable = KethMaybeRelocatable::from(address);

            // Convert back to Address
            let roundtrip_address = keth_maybe_relocatable.to_address();

            // Assert roundtrip conversion is equal to original value
            prop_assert_eq!(roundtrip_address, address);
        }

        #[test]
        fn test_bytes_to_keth_pointer_roundtrip(bytes in any::<Bytes>()) {
            // Convert to KethPointer
            let keth_pointer = KethPointer::from(bytes.clone());

            // Convert back to Bytes
            let roundtrip_bytes = keth_pointer.to_bytes();

            // Assert roundtrip conversion is equal to original value
            prop_assert_eq!(roundtrip_bytes, bytes.clone());
            prop_assert_eq!(
                keth_pointer.len.0.get_int().unwrap().to_string().parse::<usize>().unwrap(),
                bytes.len()
            );
            prop_assert_eq!(keth_pointer.type_size, 1);
            prop_assert_eq!(keth_pointer.data.len(), bytes.len());
        }

        #[test]
        fn test_signature_to_keth_pointer_roundtrip(signature in any::<Signature>()) {
            // Convert to KethPointer
            let keth_pointer = KethPointer::from(signature);
            let keth_pointer_len: usize = keth_pointer.len.to_u64() as usize;

            // Convert back to Signature
            let roundtrip_signature = keth_pointer.to_signature();

            // Assert roundtrip conversion is equal to original value
            prop_assert_eq!(roundtrip_signature, signature);
            prop_assert_eq!(keth_pointer.type_size, 1);
            prop_assert_eq!(keth_pointer_len, 5);
        }

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

        #[test]
        fn test_transaction_to_rlp_encoded(raw_bytes in any::<[u8; 1000]>()) {
            let mut unstructured = Unstructured::new(&raw_bytes);

            // Generate an arbitrary transaction
            let tx = Transaction::arbitrary(&mut unstructured)
                .expect("Failed to generate arbitrary transaction");

            // Convert the arbitrary Transaction into a Keth pointer
            let keth_rlp = KethPointer::from(tx.clone());

            // Get the encoded bytes from the Keth pointer
            let encoded_bytes = keth_rlp.to_transaction_rlp();

            // Encode the original transaction via RLP to compare with the Keth pointer
            let mut buffer = Vec::new();
            tx.encode(&mut buffer);

            // Assert that the encoded bytes from the Keth pointer match the original transaction
            prop_assert_eq!(encoded_bytes, buffer.clone());
            prop_assert_eq!(buffer.len(), keth_rlp.len.to_u64() as usize);
            prop_assert_eq!(keth_rlp.type_size, 1);
        }

        #[test]
        fn test_signed_transaction_to_transaction_encoded(raw_bytes in any::<[u8; 1000]>()) {
            let mut unstructured = Unstructured::new(&raw_bytes);

            // Generate an arbitrary signed transaction
            let tx = TransactionSigned::arbitrary(&mut unstructured)
                .expect("Failed to generate arbitrary transaction");

            // Convert the signed transaction to a keth encoded transaction
            let keth_transaction_encoded = KethTransactionEncoded::try_from(tx.clone()).unwrap();

            // Get the encoded bytes from the Keth pointer
            let encoded_bytes = keth_transaction_encoded.rlp.to_transaction_rlp();

            // Encode the original transaction via RLP to compare with the Keth pointer
            let mut buffer = Vec::new();
            tx.transaction.encode(&mut buffer);

            prop_assert_eq!(encoded_bytes, buffer.clone());
            prop_assert_eq!(buffer.len(), keth_transaction_encoded.rlp.len.to_u64() as usize);
            prop_assert_eq!(keth_transaction_encoded.rlp.type_size, 1);

            // Verify signature
            prop_assert_eq!(keth_transaction_encoded.signature.to_signature(), tx.signature);

            // Verify sender
            prop_assert_eq!(keth_transaction_encoded.sender.to_address(), tx.recover_signer().unwrap());
        }

        #[test]
        fn test_transaction_signed_ec_recovered_to_transaction_encoded(raw_bytes in any::<[u8; 1000]>()) {
            let mut unstructured = Unstructured::new(&raw_bytes);

            // Generate an arbitrary signed transaction
            let tx = TransactionSigned::arbitrary(&mut unstructured)
                .expect("Failed to generate arbitrary transaction");

            // Convert the signed transaction to EC recovered
            let tx = tx.into_ecrecovered().unwrap();

            // Convert the arbitrary Transaction into a keth encoded transaction
            let keth_transaction_encoded = KethTransactionEncoded::from(tx.clone());

            // Get the encoded bytes from the Keth pointer
            let encoded_bytes = keth_transaction_encoded.rlp.to_transaction_rlp();

            // Encode the original transaction via RLP to compare with the Keth pointer
            let mut buffer = Vec::new();
            tx.transaction.encode(&mut buffer);

            prop_assert_eq!(encoded_bytes, buffer.clone());
            prop_assert_eq!(buffer.len(), keth_transaction_encoded.rlp.len.to_u64() as usize);
            prop_assert_eq!(keth_transaction_encoded.rlp.type_size, 1);

            // Verify signature
            prop_assert_eq!(keth_transaction_encoded.signature.to_signature(), tx.signature);

            // Verify sender
            prop_assert_eq!(keth_transaction_encoded.sender.to_address(), tx.recover_signer().unwrap());
        }
    }

    #[test]
    fn test_keth_option_none() {
        let value: Option<u64> = None;
        let keth_option: KethOption<KethMaybeRelocatable> = value.into();
        assert_eq!(keth_option.is_some.0, MaybeRelocatable::from(Felt252::ZERO));
        assert_eq!(keth_option.value.0, MaybeRelocatable::from(Felt252::ZERO));
        assert_eq!(keth_option.to_option_u64(), None);
    }

    #[test]
    fn test_keth_option_some() {
        let value = 42u64;
        let keth_option: KethOption<KethMaybeRelocatable> = Some(value).into();
        assert_eq!(keth_option.is_some.0, MaybeRelocatable::from(Felt252::ONE));
        assert_eq!(keth_option.value.0, MaybeRelocatable::from(Felt252::from(value)));
        assert_eq!(keth_option.to_option_u64(), Some(value));
    }

    #[test]
    fn test_keth_u256_low_high() {
        let b256_value = B256::from([1u8; 32]); // Sample value
        let keth_u256 = KethU256::from(b256_value);

        // Verify that converting back to B256 gives the original B256
        assert_eq!(keth_u256.to_b256(), b256_value);
    }

    #[test]
    fn test_keth_u256_zero() {
        let b256_value = B256::ZERO; // All bytes are zero
        let keth_u256 = KethU256::from(b256_value);

        // Verify that converting back to B256 gives the original B256
        assert_eq!(keth_u256.to_b256(), b256_value);
    }

    #[test]
    fn test_address_to_keth_maybe_relocatable_conversion() {
        let address = Address::new([1u8; 20]); // Example address with value [1u8; 20]
        let keth_maybe_relocatable = KethMaybeRelocatable::from(address);
        assert_eq!(keth_maybe_relocatable.to_address(), address);
    }

    #[test]
    fn test_address_to_keth_maybe_relocatable_zero_address() {
        let address = Address::new([0u8; 20]); // Address with all bytes set to zero
        let keth_maybe_relocatable = KethMaybeRelocatable::from(address);
        assert_eq!(keth_maybe_relocatable.to_address(), address);
    }

    #[test]
    fn test_address_to_keth_maybe_relocatable_max_address() {
        let address = Address::new([255u8; 20]); // Max possible value for each byte
        let keth_maybe_relocatable = KethMaybeRelocatable::from(address);
        assert_eq!(keth_maybe_relocatable.to_address(), address);
    }

    #[test]
    fn test_keth_u256_from_u256_zero() {
        let u256_value = U256::ZERO; // U256 with value 0
        let keth_u256 = KethU256::from(u256_value);

        // Convert back to U256
        assert_eq!(keth_u256.to_u256(), u256_value);
    }

    #[test]
    fn test_keth_u256_from_u256_max() {
        let u256_value = U256::MAX; // U256 with max possible value (2^256 - 1)
        let keth_u256 = KethU256::from(u256_value);

        // Convert back to U256
        assert_eq!(keth_u256.to_u256(), u256_value);
    }

    #[test]
    fn test_bloom_to_keth_maybe_relocatable_zero() {
        let bloom = Bloom::ZERO;

        // Convert to KethPointer
        let keth_maybe_relocatables = KethPointer::from(bloom);

        // Verify that converting back gives the original Bloom filter
        assert_eq!(KethPointer::to_bloom(&keth_maybe_relocatables), bloom);
    }

    #[test]
    fn test_bloom_to_keth_maybe_relocatable_max() {
        let bloom_bytes = [255u8; 256]; // Max possible value for each byte
        let bloom = Bloom::from_slice(&bloom_bytes);

        // Convert to KethPointer
        let keth_maybe_relocatables = KethPointer::from(bloom);

        // Verify that converting back gives the original Bloom filter
        assert_eq!(KethPointer::to_bloom(&keth_maybe_relocatables), bloom);
        assert_eq!(
            bloom.len(),
            keth_maybe_relocatables.len.0.get_int().unwrap().to_string().parse::<usize>().unwrap()
        );
    }

    #[test]
    fn test_bloom_to_keth_maybe_relocatable() {
        for _ in 0..100 {
            let bloom = Bloom::random();

            // Convert to KethPointer
            let keth_maybe_relocatables = KethPointer::from(bloom);

            // Verify that converting back gives the original Bloom filter
            assert_eq!(KethPointer::to_bloom(&keth_maybe_relocatables), bloom);
            assert_eq!(
                bloom.len(),
                keth_maybe_relocatables
                    .len
                    .0
                    .get_int()
                    .unwrap()
                    .to_string()
                    .parse::<usize>()
                    .unwrap()
            );
        }
    }

    #[test]
    fn test_empty_bytes_conversion() {
        let bytes = Bytes::new();
        let keth_pointer = KethPointer::from(bytes.clone());
        let roundtrip_bytes = keth_pointer.to_bytes();
        assert_eq!(roundtrip_bytes, bytes);
        assert_eq!(
            keth_pointer.len.0.get_int().unwrap().to_string().parse::<usize>().unwrap(),
            bytes.len()
        );
        assert_eq!(keth_pointer.type_size, 1);
        assert_eq!(keth_pointer.data.len(), 0);
    }

    #[test]
    fn test_byte_simple_conversion() {
        let bytes = Bytes::from(vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]);
        let keth_pointer = KethPointer::from(bytes.clone());
        let roundtrip_bytes = keth_pointer.to_bytes();
        assert_eq!(roundtrip_bytes, bytes);
        assert_eq!(
            keth_pointer.len.0.get_int().unwrap().to_string().parse::<usize>().unwrap(),
            bytes.len()
        );
        assert_eq!(keth_pointer.type_size, 1);
        assert_eq!(keth_pointer.data.len(), 16);
    }
}
