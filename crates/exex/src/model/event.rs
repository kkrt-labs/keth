use super::primitives::KethPointer;
use serde::{Deserialize, Serialize};

/// Represents an Ethereum event in the Keth model.
///
/// Events are used in the Ethereum Virtual Machine (EVM) to log information during contract
/// execution. They are composed of `topics` and `data`, where:
/// - `topics`: A list of indexed fields that can be used for efficient filtering and querying.
/// - `data`: Additional unindexed information related to the event.
///
/// This struct provides a Keth-compatible representation of Ethereum events, where both `topics`
/// and `data` are stored as `KethPointer` to ensure compatibility with the Cairo VM's constraints.
#[derive(Debug, Eq, Ord, Hash, PartialEq, PartialOrd, Clone, Serialize, Deserialize)]
pub struct KethEvent {
    /// The indexed topics associated with the event.
    ///
    /// Topics allow filtering of events based on specific criteria. Each topic is typically a
    /// 256-bit value represented as a [`KethPointer`] to ensure compatibility with Cairo VM
    /// constraints.
    ///
    /// In the Cairo VM, topics are an array of Felts.
    pub topics: KethPointer,

    /// The unindexed data associated with the event.
    ///
    /// This field contains the raw data emitted by the event, which is not indexed but can
    /// provide additional context about the event.
    ///
    /// The data is stored as a [`KethPointer`] (an array of Felts in the Cairo VM).
    pub data: KethPointer,
}
