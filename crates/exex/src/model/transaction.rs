use super::primitives::{ConversionError, KethMaybeRelocatable, KethPointer};
use reth_primitives::{TransactionSigned, TransactionSignedEcRecovered};
use serde::{Deserialize, Serialize};

/// [`KethTransactionEncoded`] represents an encoded Ethereum transaction.
///
/// This struct holds three components of a transaction:
/// - The RLP (Recursive Length Prefix) encoding of the transaction.
/// - The signature of the transaction.
/// - The address of the sender.
#[derive(Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethTransactionEncoded {
    /// The RLP encoding of the transaction.
    pub rlp: KethPointer,

    /// The signature associated with the transaction.
    pub signature: KethPointer,

    /// The address of the sender.
    pub sender: KethMaybeRelocatable,
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
    use alloy_rlp::Encodable;
    use arbitrary::{Arbitrary, Unstructured};
    use proptest::prelude::*;

    proptest! {
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
            prop_assert_eq!(buffer.len(), usize::try_from(keth_transaction_encoded.rlp.len.to_u64()).unwrap());
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
            prop_assert_eq!(buffer.len(), usize::try_from(keth_transaction_encoded.rlp.len.to_u64()).unwrap());
            prop_assert_eq!(keth_transaction_encoded.rlp.type_size, 1);

            // Verify signature
            prop_assert_eq!(keth_transaction_encoded.signature.to_signature(), tx.signature);

            // Verify sender
            prop_assert_eq!(keth_transaction_encoded.sender.to_address(), tx.recover_signer().unwrap());
        }
    }
}
