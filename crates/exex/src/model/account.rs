use super::primitives::{KethDict, KethMaybeRelocatable, KethPointer};
use serde::{Deserialize, Serialize};

/// Represents an Ethereum Virtual Machine (EVM) account in the Keth execution environment.
///
/// This structure provides a Cairo-compatible representation of an EVM account, including
/// metadata, code, and storage information. Each field corresponds to an EVM concept while
/// adhering to Cairo's execution constraints.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct KethAccount {
    /// A pointer to the account's bytecode in memory.
    ///
    /// The bytecode represents the executable logic of the account.
    pub code: KethPointer,

    /// A pointer to the hash of the account's bytecode.
    ///
    /// The hash is a U256 and is used to uniquely identify the account's contract code.
    ///
    /// As the size of the pointer is known at compile time, length of the hash is not needed.
    /// The lenght is always 2:
    /// - Lower 128 bits
    /// - Higher 128 bits
    pub code_hash: KethPointer,

    /// A dictionary representing the account's persistent storage.
    ///
    /// Each key-value pair corresponds to a storage slot in the EVM.
    /// Persistent storage is maintained across transactions.
    pub storage: KethDict<KethPointer>,

    /// A dictionary for transient storage used during transaction execution.
    ///
    /// Transient storage is temporary and does not persist between transactions.
    /// It is used for intermediate computations and temporary data.
    pub transient_storage: KethDict<KethPointer>,

    /// A dictionary of valid jump destinations in the account's bytecode.
    ///
    /// This is a mapping of jump destination addresses to a boolean flag indicating whether the
    /// destination is valid.
    pub valid_jumpdests: KethDict<KethMaybeRelocatable>,

    /// The nonce of the account.
    pub nonce: KethMaybeRelocatable,

    /// A pointer to the balance of the account (Uint256 format).
    ///
    /// This field represents the amount of Ether held by the account,
    /// stored as a 256-bit unsigned integer.
    ///
    /// Length is known at compile time, so it is not needed in the pointer.
    /// The length is always 2:
    /// - Lower 128 bits
    /// - Higher 128 bits
    pub balance: KethPointer,

    /// A flag indicating whether the account is marked for self-destruction:
    /// - `0`: The account is not marked for self-destruction.
    /// - `1`: The account is marked for self-destruction.
    pub selfdestruct: KethMaybeRelocatable,

    /// A flag indicating whether the account was created during the current transaction.
    /// - `0`: The account was not created during the current transaction.
    /// - `1`: The account was created during the current transaction.
    pub created: KethMaybeRelocatable,
}
