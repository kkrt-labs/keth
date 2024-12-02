use super::primitives::{KethMaybeRelocatable, KethU256};
use serde::{Deserialize, Serialize};

/// Represents a transfer of tokens in the execution environment.
///
/// This structure captures the details of a token transfer. It is compatible with Cairo's execution
/// model and is used to finalize Starknet ETH transfers during transaction processing.
#[derive(Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethTransfer {
    /// The address of the sender initiating the transfer.
    pub sender: KethMaybeRelocatable,

    /// The address of the recipient receiving the transfer.
    pub recipient: KethMaybeRelocatable,

    /// The amount being transferred, represented as a 256-bit unsigned integer.
    pub amount: KethU256,
}
