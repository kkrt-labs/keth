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

**Why Patching is Necessary**:
Keth uses Cairo, which requires specific data structures and serialization and has some behaviors
not natively supported by the EELS library. Custom types adjust fields comparisons (e.g., adding
`code_hash`, `storage_root` in Account) and encoding to match Cairo's expectations. Patching ensures
consistency between Python logic (for input prep and testing) and Cairo logic (for proving),
preventing validation errors or incorrect proofs.

**Key Challenge - Module Loading Order**:
Python caches imported modules in `sys.modules`. If EELS modules are loaded before this
module, patches won't apply to cached modules, leading to inconsistencies. This is common
with pytest plugins that initialize early. To mitigate this, a check raises a RuntimeError
if EELS modules are already loaded, enforcing early import of this module.

**Best Practices for Maintainers**:
- **Early Import**: Import this module at the start of every entry point (scripts like
  `prove_block.py`, test configs like `conftest.py`, before the `hypothesis` entrypoint, etc) before
  any EELS imports.
- **Extend Patches**: Add new modules or attributes to the `PATCHES` dictionary below as
  needed for new EELS versions or custom types.
- **Custom Pytest Plugin**: Because pytest plugins load EELS modules early, we created a plugin
  (see `pyproject.toml`) to apply patches during plugin init.

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
    # Patches for mpt modules
    mpt.utils: {
        "Account": Account,
    },
    mpt.ethereum_tries: {
        "Account": Account,
        "EMPTY_ACCOUNT": EMPTY_ACCOUNT,
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

    **Note for Maintainers**:
    - If a new EELS module or type needs patching, update the `PATCHES` dictionary above.
    - If a module was already loaded (such as, in our example, the MPT modules), you need
      to ensure that the patch is also applied specifically to that module, and not only to
      the base ethereum modules.
    """
    # Apply patches
    for module, attributes in PATCHES.items():
        for attr_name, attr_value in attributes.items():
            logger.info(f"Patching {module.__name__}'s {attr_name}")
            setattr(module, attr_name, attr_value)


# Apply patches immediately when the module is imported
apply_patches()
