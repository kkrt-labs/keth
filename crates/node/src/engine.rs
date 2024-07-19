//! The Kakarot node implementation.

use reth_chainspec::ChainSpec;
use reth_ethereum_engine_primitives::{
    EthBuiltPayload, EthPayloadAttributes, EthPayloadBuilderAttributes, ExecutionPayloadEnvelopeV2,
    ExecutionPayloadEnvelopeV3, ExecutionPayloadEnvelopeV4, ExecutionPayloadV1,
};
use reth_node_api::{
    validate_parent_beacon_block_root_presence, EngineApiMessageVersion,
    EngineObjectValidationError, PayloadOrAttributes,
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
    type ExecutionPayloadV1 = ExecutionPayloadV1;
    type ExecutionPayloadV2 = ExecutionPayloadEnvelopeV2;
    type ExecutionPayloadV3 = ExecutionPayloadEnvelopeV3;
    type ExecutionPayloadV4 = ExecutionPayloadEnvelopeV4;

    fn validate_version_specific_fields(
        chain_spec: &ChainSpec,
        version: EngineApiMessageVersion,
        payload_or_attrs: PayloadOrAttributes<'_, EthPayloadAttributes>,
    ) -> Result<(), EngineObjectValidationError> {
        if payload_or_attrs.withdrawals().map_or(false, |w| !w.is_empty()) {
            return Err(EngineObjectValidationError::InvalidParams(
                "Withdrawals are not supported by Kakarot network".into(),
            ));
        }
        validate_parent_beacon_block_root_presence(
            chain_spec,
            version,
            payload_or_attrs.message_validation_kind(),
            payload_or_attrs.timestamp(),
            payload_or_attrs.parent_beacon_block_root().is_some(),
        )
    }
}
