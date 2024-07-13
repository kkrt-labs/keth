//! Transaction validation logic.

use reth_chainspec::ChainSpec;
use reth_transaction_pool::{
    validate::{EthTransactionValidator, EthTransactionValidatorBuilder},
    BlobStore,
};
use std::sync::Arc;

/// A wrapper around the Reth [`EthTransactionValidatorBuilder`].
/// The produced Validator will reject EIP4844 transactions not supported by Kakarot at the moment.
#[derive(Debug)]
pub struct KakarotTransactionValidatorBuilder(EthTransactionValidatorBuilder);

impl KakarotTransactionValidatorBuilder {
    /// Create a new [`EthTransactionValidatorBuilder`].
    pub fn new(chain_spec: Arc<ChainSpec>) -> Self {
        Self(EthTransactionValidatorBuilder::new(chain_spec))
    }

    /// Build the [`EthTransactionValidator`]. Force `no_eip4844`.
    pub fn build<Client, S>(self, client: Client, store: S) -> EthTransactionValidator<Client, S>
    where
        S: BlobStore,
    {
        self.0.no_eip4844().build(client, store)
    }
}
