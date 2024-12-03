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
    /// This implementation encodes the `topics` and `data` from the [`LogData`] structure into
    /// the Keth model format compatible with the Cairo VM.
    fn from(value: LogData) -> Self {
        // Convert the topics into a flat array of 256-bit values
        // For each topic, we convert it into a `KethU256` and then split it into:
        // - The low 128 bits
        // - The high 128 bits
        let topics: Vec<_> = value
            .topics()
            .iter()
            .flat_map(|topic| {
                let t: KethU256 = (*topic).into();
                [t.low, t.high]
            })
            .collect();

        let topics = KethPointer { len: Some(topics.len().into()), data: topics, type_size: 1 };

        Self { topics, data: value.data.into() }
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
