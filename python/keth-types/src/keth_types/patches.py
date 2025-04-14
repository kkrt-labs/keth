"""
keth_types.patches
~~~~~~~~~~~~

This module centralizes patches for third-party modules (e.g., ethereum, mpt) to use
custom types defined in keth.types. These patches ensure compatibility between
Keth's Cairo-based prover and the Ethereum EELS library by overriding default types like
Account, Evm, and Message.

Patches are applied when this module is imported, ensuring they take effect before any
other code runs. Each patch targets the original definition in its source module to avoid
redundant hot-patching of imported references.

Usage:
    Import this module at the start of any entry point (e.g., scripts, tests) to apply patches.
    Example: `import keth_types.patches`
"""

import logging
from typing import Any, Dict, Sequence, Union

import ethereum
import ethereum.cancun
import ethereum_rlp
from ethereum_types.numeric import FixedUnsigned, Uint

import mpt
from keth_types.types import (
    EMPTY_ACCOUNT,
    Account,
    Environment,
    Evm,
    Message,
    MessageCallOutput,
    Node,
    encode_account,
    is_account_alive,
    set_code,
)

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()

# Dictionary mapping modules to their attributes and patched values
PATCHES: Dict[Any, Dict[str, Any]] = {
    ethereum.cancun.fork_types: {
        "Account": Account,
        "EMPTY_ACCOUNT": EMPTY_ACCOUNT,
        "encode_account": encode_account,
    },
    ethereum.cancun.state: {
        "is_account_alive": is_account_alive,
        "set_code": set_code,
    },
    ethereum.cancun.vm: {
        "Evm": Evm,
        "Message": Message,
        "Environment": Environment,
    },
    ethereum.cancun.trie: {
        "Node": Node,
    },
    ethereum.cancun.vm.interpreter: {
        "MessageCallOutput": MessageCallOutput,
    },
    ethereum_rlp.rlp: {
        "Extended": Union[Sequence["Extended"], bytearray, bytes, Uint, FixedUnsigned, str, bool]  # type: ignore # noqa: F821,  # Simplified for brevity; refine as needed
    },
    mpt.trie_diff: {
        "Account": Account,
    },
}


def apply_patches() -> None:
    """
    Apply all patches defined in PATCHES to their respective modules.

    This function sets attributes on the target modules to override their original
    definitions with custom types. It is called automatically when this module is imported.
    """
    # Remove all ethereum modules from sys.modules

    # Apply patches
    for module, attributes in PATCHES.items():
        for attr_name, attr_value in attributes.items():
            logger.info(f"Patching {module.__name__} with {attr_name}")
            setattr(module, attr_name, attr_value)


# Apply patches immediately when the module is imported
apply_patches()
