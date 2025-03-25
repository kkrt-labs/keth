from ethereum.cancun.trie import BranchNode, ExtensionNode, InternalNode

from mpt.trie_diff import resolve
from mpt.utils import deserialize_to_internal_node


def test_embedded_nodes_resolve(branch_in_extension_data):
    """
    Test that decodes and resolves embedded nodes.
    """

    def check_node_and_subnodes(node: InternalNode):
        match node:
            case BranchNode():
                for subnode in node.subnodes:
                    # embedded nodes are a list of decoded bytes that need to be serialized into an InternalNode
                    if isinstance(subnode, list):
                        resolved = resolve(subnode, nodes)
                        assert resolved == deserialize_to_internal_node(subnode)
                        # Recursively check the resolved node
                        check_node_and_subnodes(resolved)
            case ExtensionNode():
                # extension nodes are a list of decoded bytes that need to be serialized into an InternalNode
                if isinstance(node.subnode, list):
                    resolved = resolve(node.subnode, nodes)
                    assert resolved == deserialize_to_internal_node(node.subnode)
                    # Recursively check the resolved node
                    check_node_and_subnodes(resolved)
            case _:
                return

    # Start checking each node in the test data
    nodes = branch_in_extension_data["nodes"]
    for node in nodes.values():
        check_node_and_subnodes(node)
