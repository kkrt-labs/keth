use super::primitives::{KethPointer, KethU256};
use alloy_primitives::LogData;
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

impl From<LogData> for KethEvent {
    /// Converts a [`LogData`] object into a [`KethEvent`].
    ///
    /// This function transforms the `topics` and `data` from the Ethereum-compatible [`LogData`]
    /// structure into the Cairo VM-compatible [`KethEvent`] representation.
    ///
    /// # Details
    /// - Each topic (`B256`) is split into two 128-bit components (`low` and `high`) and stored as
    ///   `KethMaybeRelocatable` values.
    /// - The `data` is directly converted into a [`KethPointer`] with each byte represented as a
    ///   felt.
    fn from(log_data: LogData) -> Self {
        // Flatten each topic into its low and high components as `KethMaybeRelocatable`.
        let encoded_topics: Vec<_> = log_data
            .topics()
            .iter()
            .flat_map(|topic| {
                let keth_u256: KethU256 = (*topic).into();
                [keth_u256.low, keth_u256.high]
            })
            .collect();

        // Create a `KethPointer` for topics with the calculated length.
        let topic_pointer = KethPointer {
            len: Some(encoded_topics.len().into()),
            data: encoded_topics,
            type_size: 1,
        };

        // Convert data directly into a `KethPointer`.
        let data_pointer = log_data.data.into();

        // Return the `KethEvent`.
        Self { topics: topic_pointer, data: data_pointer }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use alloy_primitives::{Bytes, B256};
    use proptest::prelude::*;

    impl KethEvent {
        /// Converts a [`KethEvent`] into a [`LogData`].
        ///
        /// This implementation reverses the encoding done during the [`LogData`] to [`KethEvent`]
        /// conversion, extracting `topics` and `data` back into their original format.
        fn to_log_data(&self) -> LogData {
            // Convert topics: Each `B256` is represented by two `KethMaybeRelocatable` values:
            // - The low 128 bits
            // - The high 128 bits
            let topics = self
                .topics
                .data
                .chunks_exact(2) // Each `B256` is split into 2 parts.
                .map(|chunk| KethU256 { low: chunk[0].clone(), high: chunk[1].clone() }.to_b256())
                .collect();

            // Convert data directly to `Bytes`.
            let data = self.data.to_bytes();

            LogData::new_unchecked(topics, data)
        }
    }

    proptest! {
        #[test]
        fn test_log_data_to_keth_event_roundtrip(log_data in any::<LogData>()) {
            // Convert LogData to KethEvent
            let keth_event: KethEvent = log_data.clone().into();

            // Convert back to LogData
            let roundtrip_log_data: LogData = keth_event.to_log_data();

            // Assert roundtrip conversion is equal to the original value
            prop_assert_eq!(roundtrip_log_data, log_data);
        }
    }

    #[test]
    fn test_empty_log_data_conversion() {
        let log_data = LogData::default();
        let keth_event: KethEvent = log_data.clone().into();
        let roundtrip_log_data: LogData = keth_event.to_log_data();
        assert_eq!(roundtrip_log_data, log_data);
    }

    #[test]
    fn test_single_topic_and_data_conversion() {
        let log_data = LogData::new_unchecked(vec![B256::from([1u8; 32])], Bytes::from(vec![0x42]));
        let keth_event: KethEvent = log_data.clone().into();
        let roundtrip_log_data: LogData = keth_event.to_log_data();
        assert_eq!(roundtrip_log_data, log_data);
    }

    #[test]
    fn test_multiple_topics_and_data_conversion() {
        let log_data = LogData::new_unchecked(
            vec![B256::from([1u8; 32]), B256::from([2u8; 32])],
            Bytes::from(vec![0x42, 0x43, 0x44]),
        );
        let keth_event: KethEvent = log_data.clone().into();
        let roundtrip_log_data: LogData = keth_event.to_log_data();
        assert_eq!(roundtrip_log_data, log_data);
    }
}
