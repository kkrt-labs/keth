//! The Kakarot mempool implementation.
//!
//! ## Overview
//!
//! The mempool crate provides the core logic for managing transactions in the mempool.
//!
//! ## Implementation
//!
//! The Kakarot mempool implementation reuses where possible components from the Reth
//! [mempool implementation](https://github.com/paradigmxyz/reth/tree/main/crates/transaction-pool/src).

pub mod validate;

use crate::validate::KakarotEthTransactionValidator;
use reth_node_ethereum::node::EthereumPoolBuilder;
use reth_transaction_pool::{
    CoinbaseTipOrdering, EthPooledTransaction, Pool, TransactionValidationTaskExecutor,
};

/// A type alias for the Kakarot Transaction Validator.
/// Uses the Reth implementation [`TransactionValidationTaskExecutor`].
pub type Validator<Client> =
    TransactionValidationTaskExecutor<KakarotEthTransactionValidator<Client, EthPooledTransaction>>;

/// A type alias for the Kakarot Transaction Ordering.
/// Uses the Reth implementation [`CoinbaseTipOrdering`].
pub type TransactionOrdering = CoinbaseTipOrdering<EthPooledTransaction>;

/// A type alias for the Kakarot Sequencer Mempool.
pub type KakarotPool<Client, S> = Pool<Validator<Client>, TransactionOrdering, S>;

/// Type alias for the Kakarot mempool builder.
///
/// This type alias represents the configuration builder for the mempool used in the Kakarot
/// implementation, utilizing components from the Ethereum node framework provided by Reth.
///
/// It configures the transaction pool specific to Kakarot's requirements.
/// TODO: incorrect, this needs to use the custom Validator<Client>.
pub type KakarotPoolBuilder = EthereumPoolBuilder;
