use alloy_primitives::{Address, Bloom, B256, U256};
use cairo_vm::{types::relocatable::MaybeRelocatable, Felt252};
use serde::{Deserialize, Serialize};

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
/// any type, such as [`KethMaybeRelocatable`] or [`KethU256`], specifically tailored for use
/// within the Keth model inside our OS.
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
            low: KethMaybeRelocatable::from_bytes_be_slice(&value.0[16..]),
            high: KethMaybeRelocatable::from_bytes_be_slice(&value.0[0..16]),
        }
    }
}

impl From<U256> for KethU256 {
    fn from(value: U256) -> Self {
        Self {
            low: KethMaybeRelocatable::from_bytes_be_slice(
                &value.to_be_bytes::<{ U256::BYTES }>()[16..],
            ),
            high: KethMaybeRelocatable::from_bytes_be_slice(
                &value.to_be_bytes::<{ U256::BYTES }>()[0..16],
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
    /// - The `data` field stores the remaining elements as chunks of 16 bytes each from the Bloom
    ///   filter, with each chunk converted into a [`KethMaybeRelocatable`].
    ///
    /// This process allows the 256-byte Bloom filter to be stored and processed efficiently in the
    /// `KethPointer` structure, making it compatible with CairoVM's constraints.
    fn from(value: Bloom) -> Self {
        Self {
            // The length of the Bloom filter.
            len: value.len().into(),
            // Chunk the 256-byte array into groups of 16 bytes and convert.
            data: value.0.chunks(16).map(KethMaybeRelocatable::from_bytes_be_slice).collect(),
            // In Cairo, Bloom is a pointer to a segment of felts.
            type_size: 1,
        }
    }
}

// TODO: uncomment this in follow-up PRs
// pub struct KethBlockHeader {
//     base_fee_per_gas: KethMaybeRelocatable,
//     blob_gas_used: KethMaybeRelocatable,
//     bloom_len: KethMaybeRelocatable,
//     bloom: Vec<KethMaybeRelocatable>,
//     coinbase: KethMaybeRelocatable,
//     difficulty: KethMaybeRelocatable,
//     excess_blob_gas: KethMaybeRelocatable,
//     extra_data_len: KethMaybeRelocatable,
//     extra_data: Vec<KethMaybeRelocatable>,
//     gas_limit: KethMaybeRelocatable,
//     gas_used: KethMaybeRelocatable,
//     hash: KethU256,
//     mix_hash: KethU256,
//     nonce: KethMaybeRelocatable,
//     number: KethMaybeRelocatable,
//     parent_beacon_block_root: KethU256,
//     parent_hash: KethU256,
//     receipt_trie: KethU256,
//     state_root: KethU256,
//     timestamp: KethMaybeRelocatable,
//     transactions_trie: KethU256,
//     uncle_hash: KethU256,
//     withdrawals_root: KethU256,
// }

#[cfg(test)]
mod tests {
    use super::*;
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
                &high_bytes[16..], // Get the high 16 bytes
                &low_bytes[16..],  // Get the low 16 bytes
            ]
            .concat();
            B256::from_slice(&bytes)
        }

        /// Convert KethU256 back to U256.
        fn to_u256(&self) -> U256 {
            let high_bytes = self.high.0.get_int().unwrap().to_bytes_be();
            let low_bytes = self.low.0.get_int().unwrap().to_bytes_be();
            let bytes = [
                &high_bytes[16..], // Get the high 16 bytes
                &low_bytes[16..],  // Get the low 16 bytes
            ]
            .concat();
            U256::from_be_slice(&bytes)
        }
    }

    impl KethMaybeRelocatable {
        fn to_address(&self) -> Address {
            // Get the bytes in big-endian order
            let bytes = self.0.get_int().unwrap().to_bytes_be();
            // Extract the last 20 bytes to get the address
            Address::from_slice(&bytes[bytes.len() - Address::len_bytes()..])
        }
    }

    impl KethPointer {
        fn to_bloom(keth_maybe_relocatables: &KethPointer) -> Bloom {
            Bloom::from_slice(
                &keth_maybe_relocatables
                    .data
                    .iter()
                    .flat_map(|item| item.0.get_int().unwrap().to_bytes_be()[16..].to_vec())
                    .collect::<Vec<_>>(),
            )
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
}
