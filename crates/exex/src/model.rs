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
    /// let one_value = KethMaybeRelocatable::one();
    /// ```
    pub fn one() -> Self {
        Self(Felt252::ONE.into())
    }
}

impl From<Felt252> for KethMaybeRelocatable {
    fn from(value: Felt252) -> Self {
        Self(value.into())
    }
}

impl From<u64> for KethMaybeRelocatable {
    fn from(value: u64) -> Self {
        Self(Felt252::from(value).into())
    }
}

/// [`KethOption`] is a custom representation of a Rust [`Option<u64>`] type, specifically tailored
/// for use within the Keth model inside our OS.
///
/// This struct encapsulates two fields:
/// - `is_some`: A flag that indicates whether the option contains a value (`is_some = 1`) or is
///   empty (`is_some = 0`).
/// - `value`: The actual value of the option, represented as a [`KethMaybeRelocatable`].
///
/// When the option is [`None`], the `value` field is assigned a default zero value. This struct
/// provides a way to handle optional values in a manner consistent with the Keth model's memory
/// representation.
#[derive(Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethOption {
    /// Indicates whether the option contains a value ([`Some`]) or is empty ([`None`]).
    /// - When set to `1`, it indicates the presence of a value.
    /// - When set to `0`, it represents a [`None`] value.
    is_some: KethMaybeRelocatable,

    /// The value stored in the option, wrapped inside [`KethMaybeRelocatable`].
    ///
    /// If the option is [`None`], this field holds a zero value.
    value: KethMaybeRelocatable,
}

impl Default for KethOption {
    fn default() -> Self {
        Self { is_some: KethMaybeRelocatable::zero(), value: KethMaybeRelocatable::zero() }
    }
}

impl From<Option<u64>> for KethOption {
    fn from(value: Option<u64>) -> Self {
        match value {
            Some(value) => KethOption { is_some: Felt252::ONE.into(), value: value.into() },
            None => KethOption::default(),
        }
    }
}

// TODO: uncomment this in follow-up PRs
// pub struct KethU256 {
//     low: KethMaybeRelocatable,
//     high: KethMaybeRelocatable,
// }

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

    impl KethOption {
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
    }

    #[test]
    fn test_keth_option_none() {
        let keth_option = KethOption::from(None);
        assert_eq!(keth_option.is_some.0, MaybeRelocatable::from(Felt252::ZERO));
        assert_eq!(keth_option.value.0, MaybeRelocatable::from(Felt252::ZERO));
        assert_eq!(keth_option.to_option_u64(), None);
    }

    #[test]
    fn test_keth_option_some() {
        let value = 42u64;
        let keth_option = KethOption::from(Some(value));
        assert_eq!(keth_option.is_some.0, MaybeRelocatable::from(Felt252::ONE));
        assert_eq!(keth_option.value.0, MaybeRelocatable::from(Felt252::from(value)));
        assert_eq!(keth_option.to_option_u64(), Some(value));
    }
}
