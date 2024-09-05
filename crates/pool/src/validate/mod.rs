//! Transaction validation logic.

use reth_chainspec::ChainSpec;
use reth_transaction_pool::{
    validate::{EthTransactionValidator, EthTransactionValidatorBuilder},
    BlobStore,
};
use std::sync::Arc;

/// A wrapper around the Reth [`EthTransactionValidator`].
/// The produced Validator will reject EIP4844 transactions not supported by Kakarot at the moment.
#[derive(Debug)]
pub struct KakarotTransactionValidatorBuilder(EthTransactionValidatorBuilder);

impl KakarotTransactionValidatorBuilder {
    /// Create a new [`EthTransactionValidatorBuilder`].
    pub fn new(chain_spec: Arc<ChainSpec>) -> Self {
        Self(EthTransactionValidatorBuilder::new(chain_spec))
    }

    /// Build the [`EthTransactionValidator`].
    pub fn build<Client, S>(
        self,
        client: Client,
        store: S,
    ) -> KakarotEthTransactionValidator<Client, S>
    where
        S: BlobStore,
    {
        let validator = self.0.build(client, store);
        KakarotEthTransactionValidator { inner: validator }
    }
}

/// A wrapper around the Reth [`EthTransactionValidator`].
#[derive(Debug)]
pub struct KakarotEthTransactionValidator<Client, S> {
    pub inner: EthTransactionValidator<Client, S>,
}
