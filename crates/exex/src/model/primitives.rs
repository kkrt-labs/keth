use super::payload::{KethEncodable, KethPayload};
use alloy_primitives::{Address, Bloom, Bytes, Signature, B256, B64, U256};
use alloy_rlp::Encodable;
use cairo_vm::{types::relocatable::MaybeRelocatable, Felt252};
use reth_primitives::Transaction;
use serde::{Deserialize, Serialize};
use thiserror::Error;

/// This represents the possible errors that can occur during conversions from Ethereum format to
/// Cairo VM compatible formats.
#[derive(Error, Debug)]
pub enum ConversionError {
    /// Error indicating the failure to recover the signer from the transaction.
    #[error("Failed to recover signer from transaction")]
    TransactionSigner,
}

/// The size in bytes of the `u128` type.
pub const U128_BYTES_SIZE: usize = std::mem::size_of::<u128>();

/// A custom wrapper around [`MaybeRelocatable`] for the Keth execution environment.
///
/// This struct serves as a utility for wrapping [`MaybeRelocatable`] values in Keth, which uses
/// [`Felt252`] as the core type to represent numerical values within its system.
///
/// Additionally, this wrapper facilitates operations such as conversions between different Keth
/// types, making it easier to work with the underlying data structures.
///
/// # Usage
/// - This type is primarily used for wrapping values in Keth, enabling smooth interoperability
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
    /// use kakarot_exex::model::primitives::KethMaybeRelocatable;
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
    /// use kakarot_exex::model::primitives::KethMaybeRelocatable;
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
    /// use kakarot_exex::model::primitives::KethMaybeRelocatable;
    ///
    /// let bytes: &[u8] = &[0x00, 0x01, 0x02, 0x03]; // Example big-endian byte array
    /// let keth_value = KethMaybeRelocatable::from_bytes_be_slice(bytes);
    /// ```
    pub fn from_bytes_be_slice(bytes: &[u8]) -> Self {
        Felt252::from_bytes_be_slice(bytes).into()
    }
}

impl KethEncodable for KethMaybeRelocatable {
    fn encode(&self) -> KethPayload {
        KethPayload::Flat(vec![self.0.clone()])
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

impl<T: KethEncodable + Default> KethEncodable for KethOption<T> {
    fn encode(&self) -> KethPayload {
        // Determine the presence flag
        let is_some = self.is_some.0.clone();

        // Encode the value (default if not present)
        let value = if self.is_some.0 == MaybeRelocatable::from(Felt252::ONE) {
            Box::new(self.value.encode())
        } else {
            Box::new(T::default().encode())
        };

        // Create an `Option` payload
        KethPayload::Option { is_some, value }
    }
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
    Self: Default,
{
    fn from(value: Option<T>) -> Self {
        value.map_or_else(Self::default, |value| Self {
            is_some: KethMaybeRelocatable::one(),
            value: value.into(),
        })
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

impl KethEncodable for KethU256 {
    fn encode(&self) -> KethPayload {
        KethPayload::Flat(vec![self.low.0.clone(), self.high.0.clone()])
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
/// a format that can be stored and processed by the Cairo VM.
///
/// It efficiently stores 256-bit values and provides an interface for converting data structures
/// into a compatible format.
#[derive(Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethPointer {
    /// The length of the data to be stored.
    pub len: KethMaybeRelocatable,

    /// A vector holding the main data.
    pub data: Vec<KethMaybeRelocatable>,

    /// The size of the underlying Cairo struct (see `.SIZE`)
    ///
    /// By default, this is set to 1, which is the size of a single felt in Cairo.
    pub type_size: usize,
}

impl Default for KethPointer {
    fn default() -> Self {
        Self { len: KethMaybeRelocatable::zero(), data: Vec::new(), type_size: 1 }
    }
}

impl KethEncodable for KethPointer {
    fn encode(&self) -> KethPayload {
        KethPayload::Pointer {
            len: self.len.0.clone(),
            data: Box::new(KethPayload::Flat(
                self.data.iter().map(|item| item.0.clone()).collect(),
            )),
        }
    }
}

impl From<Bloom> for KethPointer {
    /// Converts a [`Bloom`] filter into a [`KethPointer`] structure.
    ///
    /// The [`Bloom`] filter is represented as a 256-byte array in big-endian order. Since
    /// Cairo VM's [`Felt252`] can only handle values up to 252 bits, we need to break the
    /// 256-byte array into smaller chunks that fit within this limit.
    ///
    /// The conversion process works as follows:
    /// - The first field (`len`) holds the length of the original data, represented as a
    ///   [`KethMaybeRelocatable`].
    /// - The `data` field stores the remaining elements as chunks of [`U128_BYTES_SIZE`] bytes each
    ///   from the Bloom filter, with each chunk converted into a [`KethMaybeRelocatable`].
    ///
    /// This process allows the 256-byte Bloom filter to be stored and processed efficiently in the
    /// `KethPointer` structure, making it compatible with Cairo VM's constraints.
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
    /// converts it into the [`KethPointer`] format, making it compatible with Cairo VM's
    /// 252-bit limitation for [`Felt252`] values.
    ///
    /// The conversion process:
    /// - The `len` field represents the total length of the input bytes, converted into a
    ///   [`KethMaybeRelocatable`] value.
    /// - The `data` field maps each byte of the input to a [`KethMaybeRelocatable`] value
    ///   (represented as a [`Felt252`] in Cairo VM). This approach ensures that each byte is
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
            data: buffer.into_iter().map(Into::into).collect(),
            // Set the type size to `1`, meaning this is a single segment in Cairo.
            type_size: 1,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use arbitrary::{Arbitrary, Unstructured};
    use proptest::prelude::*;

    impl KethOption<KethMaybeRelocatable> {
        /// Helper function to convert [`KethOption`] to [`Option<u64>`]
        pub fn to_option_u64(&self) -> Option<u64> {
            if self.is_some.0 == MaybeRelocatable::from(Felt252::ONE) {
                // Convert value back to u64 if present
                match &self.value.0 {
                    MaybeRelocatable::Int(felt) => Some(felt.to_string().parse::<u64>().unwrap()),
                    MaybeRelocatable::RelocatableValue(_) => None, // Should never happen
                }
            } else {
                None
            }
        }
    }

    impl KethOption<KethU256> {
        /// Helper function to convert [`KethOption`] to [`Option<B256>`]
        pub fn to_option_b256(&self) -> Option<B256> {
            if self.is_some.0 == MaybeRelocatable::from(Felt252::ONE) {
                // Convert value back to B256 if present
                Some(self.value.to_b256())
            } else {
                None
            }
        }
    }

    impl KethU256 {
        /// Convert [`KethU256`] back to [`B256`].
        pub fn to_b256(&self) -> B256 {
            let high_bytes = self.high.0.get_int().unwrap().to_bytes_be();
            let low_bytes = self.low.0.get_int().unwrap().to_bytes_be();
            let bytes = [
                &high_bytes[U128_BYTES_SIZE..], // Get the high 16 bytes
                &low_bytes[U128_BYTES_SIZE..],  // Get the low 16 bytes
            ]
            .concat();
            B256::from_slice(&bytes)
        }

        /// Convert [`KethU256`] back to [`U256`].
        pub fn to_u256(&self) -> U256 {
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
        pub fn to_u64(&self) -> u64 {
            self.0.get_int().unwrap().to_string().parse::<u64>().unwrap()
        }

        pub fn to_address(&self) -> Address {
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
        pub fn to_bytes(&self) -> Bytes {
            Bytes::from(
                self.data
                    // Iterate through the items in the `data` field.
                    .iter()
                    // For each item, retrieve its integer value and convert to big-endian bytes.
                    .filter_map(|item| {
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
        pub fn to_bloom(&self) -> Bloom {
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
        pub fn to_signature(&self) -> Signature {
            let r = KethU256 { low: self.data[0].clone(), high: self.data[1].clone() }.to_u256();
            let s = KethU256 { low: self.data[2].clone(), high: self.data[3].clone() }.to_u256();
            let v = self.data[4].clone().to_u64();

            Signature::from_rs_and_parity(r, s, v).expect("Failed to create signature")
        }

        /// Util to convert the [`KethPointer`] to RLP encoded transaction bytes.
        pub fn to_transaction_rlp(&self) -> Vec<u8> {
            // Extract the bytes from the data field
            self.data
                .iter()
                .map(|item| item.0.get_int().unwrap().to_string().parse::<u8>().unwrap())
                .collect::<Vec<_>>()
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
            let bytes_len = bytes.len();
            prop_assert_eq!(roundtrip_bytes, bytes);
            prop_assert_eq!(
                keth_pointer.len.0.get_int().unwrap().to_string().parse::<usize>().unwrap(),
                bytes_len
            );
            prop_assert_eq!(keth_pointer.type_size, 1);
            prop_assert_eq!(keth_pointer.data.len(),bytes_len);
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
