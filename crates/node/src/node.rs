use crate::execution::KakarotExecutorBuilder;
use kakarot_pool::KakarotPoolBuilder;
use reth_chainspec::ChainSpec;
use reth_ethereum_engine_primitives::{
    EthBuiltPayload, EthPayloadAttributes, EthPayloadBuilderAttributes,
};
use reth_node_builder::{
    components::ComponentsBuilder, FullNodeTypes, Node, NodeTypes, NodeTypesWithEngine,
    PayloadTypes,
};
use reth_node_ethereum::{
    node::{
        EthereumAddOns, EthereumConsensusBuilder, EthereumNetworkBuilder, EthereumPayloadBuilder,
    },
    EthEngineTypes,
};

/// Type alias for the Kakarot payload builder.
pub type KakarotPayloadBuilder = EthereumPayloadBuilder;

/// Type alias for the Kakarot network builder.
/// TODO: we don't need a network for now, so just implement a type that does nothing.
pub type KakarotNetworkBuilder = EthereumNetworkBuilder;

/// Type alias for the Kakarot consensus builder.
/// TODO: we don't need a consensus for now, so just implement a type that does nothing.
pub type KakarotConsensusBuilder = EthereumConsensusBuilder;

/// Type alias for the Kakarot add-ons.
pub type KakarotAddsOns = EthereumAddOns;

/// Type configuration for a regular Kakarot node.
#[derive(Debug, Default, Clone, Copy)]
#[non_exhaustive]
pub struct KakarotNode;

impl KakarotNode {
    /// Returns a [`ComponentsBuilder`] configured for a regular Kakarot node.
    pub fn components<Node>() -> ComponentsBuilder<
        Node,
        KakarotPoolBuilder,
        KakarotPayloadBuilder,
        KakarotNetworkBuilder,
        KakarotExecutorBuilder,
        KakarotConsensusBuilder,
    >
    where
        Node: FullNodeTypes<Types: NodeTypes<ChainSpec = ChainSpec>>,
        <Node::Types as NodeTypesWithEngine>::Engine: PayloadTypes<
            BuiltPayload = EthBuiltPayload,
            PayloadAttributes = EthPayloadAttributes,
            PayloadBuilderAttributes = EthPayloadBuilderAttributes,
        >,
    {
        ComponentsBuilder::default()
            .node_types::<Node>()
            .pool(KakarotPoolBuilder::default())
            .payload(KakarotPayloadBuilder::default())
            .network(KakarotNetworkBuilder::default())
            .executor(KakarotExecutorBuilder::default())
            .consensus(KakarotConsensusBuilder::default())
    }
}

impl NodeTypes for KakarotNode {
    type Primitives = ();
    type ChainSpec = ChainSpec;
}

impl NodeTypesWithEngine for KakarotNode {
    type Engine = EthEngineTypes;
}

impl<Types, N> Node<N> for KakarotNode
where
    Types: NodeTypesWithEngine<Engine = EthEngineTypes, ChainSpec = ChainSpec>,
    N: FullNodeTypes<Types = Types>,
{
    type ComponentsBuilder = ComponentsBuilder<
        N,
        KakarotPoolBuilder,
        KakarotPayloadBuilder,
        KakarotNetworkBuilder,
        KakarotExecutorBuilder,
        KakarotConsensusBuilder,
    >;

    type AddOns = KakarotAddsOns;

    fn components_builder(&self) -> Self::ComponentsBuilder {
        Self::components()
    }
}
