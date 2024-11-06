//! The Kakarot node implementation.

use reth_ethereum_engine_primitives::{
    EthBuiltPayload, EthPayloadAttributes, EthPayloadBuilderAttributes, ExecutionPayloadEnvelopeV2,
    ExecutionPayloadEnvelopeV3, ExecutionPayloadEnvelopeV4, ExecutionPayloadV1,
};
use reth_node_builder::{EngineTypes, PayloadTypes};
use serde::{Deserialize, Serialize};

/// The types used in the default mainnet ethereum beacon consensus engine.
#[derive(Debug, Default, Clone, Deserialize, Serialize)]
#[non_exhaustive]
pub struct KakarotEngineTypes;

impl PayloadTypes for KakarotEngineTypes {
    type BuiltPayload = EthBuiltPayload;
    type PayloadAttributes = EthPayloadAttributes;
    type PayloadBuilderAttributes = EthPayloadBuilderAttributes;
}

impl EngineTypes for KakarotEngineTypes {
    type ExecutionPayloadEnvelopeV1 = ExecutionPayloadV1;
    type ExecutionPayloadEnvelopeV2 = ExecutionPayloadEnvelopeV2;
    type ExecutionPayloadEnvelopeV3 = ExecutionPayloadEnvelopeV3;
    type ExecutionPayloadEnvelopeV4 = ExecutionPayloadEnvelopeV4;
}
