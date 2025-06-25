"""
keth_types.patches
~~~~~~~~~~~~

This module centralizes patches for third-party modules (e.g., ethereum, mpt) to use
custom types defined in keth.types. These patches ensure compatibility between
Keth's Cairo-based prover and the Ethereum EELS library by overriding default types like
Account, Evm, and Message.

Patches are applied when this module is imported, ensuring they take effect before any
other code runs. Each patch targets replaces all instances of the original attribute with
the patched version in any module where it is accessible.

**Why Patching is Necessary**:
Keth uses Cairo, which requires specific data structures and serialization and has some behaviors
not natively supported by the EELS library. Custom types adjust fields comparisons (e.g., adding
`code_hash`, `storage_root` in Account) and encoding to match Cairo's expectations. Patching ensures
consistency between Python logic (for input prep and testing) and Cairo logic (for proving),
preventing validation errors or incorrect proofs.

**Key Challenge - Module Loading Order**:
Python caches imported modules in `sys.modules`. If EELS modules are loaded before this
module, patches won't apply to cached modules, leading to inconsistencies. To mitigate this,
we import this module at the start of every entry point (scripts like `prove_block.py`, test
configs like `conftest.py`, before the `hypothesis` entrypoint, etc) before any EELS imports, but
this is not always sufficient. As such, the best approach is to simply iterate through all the already loaded
modules and patch them.

**Best Practices for Maintainers**:
- **Early Import**: Import this module at the start of every entry point (scripts like
  `prove_block.py`, test configs like `conftest.py`, before the `hypothesis` entrypoint, etc) before
  any EELS imports.
- **Extend Patches**: Add new modules or attributes to the `PATCHES` dictionary below as
  needed for new EELS versions or custom types.
- **Custom Pytest Plugin**: Because pytest plugins load EELS modules early, we created a plugin
  (see `pyproject.toml`) to apply patches during plugin init. This plugin gets automatically called
  during pytest plugin init, ensuring it runs before any other code.

Usage:
    Import this module at the start of any entry point (e.g., scripts, tests) to apply patches.
    Example: `import keth_types.patches`
"""

import logging
from typing import Any, Dict, Sequence, Union

import ethereum
import ethereum.prague
import ethereum_rlp
from ethereum_types.numeric import FixedUnsigned, Uint

from keth_types.types import (
    EMPTY_ACCOUNT,
    Account,
    BlockEnvironment,
    Evm,
    Message,
    MessageCallOutput,
    Node,
    TransactionEnvironment,
    account_exists_and_is_empty,
    encode_account,
    is_account_alive,
    set_code,
)

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger()

# Dictionary mapping modules to their attributes and patched values for explicit patching
PATCHES: Dict[str, Dict[str, Any]] = {
    ethereum.prague.fork_types: {
        "Account": Account,
        "EMPTY_ACCOUNT": EMPTY_ACCOUNT,
        "encode_account": encode_account,
    },
    ethereum.prague.state: {
        "account_exists_and_is_empty": account_exists_and_is_empty,
        "is_account_alive": is_account_alive,
        "set_code": set_code,
    },
    ethereum.prague.vm: {
        "Evm": Evm,
        "Message": Message,
        "BlockEnvironment": BlockEnvironment,
        "TransactionEnvironment": TransactionEnvironment,
    },
    ethereum.prague.trie: {
        "Node": Node,
    },
    ethereum.prague.vm.interpreter: {
        "MessageCallOutput": MessageCallOutput,
    },
    ethereum_rlp.rlp: {
        "Extended": Union[Sequence["Extended"], bytearray, bytes, Uint, FixedUnsigned, str, bool]  # type: ignore # noqa: F821
    },
}


def apply_patches() -> None:
    """
    Apply patches using a hybrid approach:
    1. Explicitly patch specific modules as defined in PATCHES, importing them if necessary.
    2. Dynamically patch all already loaded modules under 'ethereum' and 'mpt' packages.
    """
    import sys
    from types import ModuleType
    from typing import Any, Dict

    def patch_module(module: ModuleType, attr_name: str, attr_value: Any) -> None:
        if hasattr(module, attr_name):
            logger.debug(f"Patching {module.__name__}'s {attr_name}")
            setattr(module, attr_name, attr_value)

    all_attrs: Dict[str, Any] = {
        k: v for attrs in PATCHES.values() for k, v in attrs.items()
    }

    # Step 1: Explicit patching of modules items are defined in
    for module, attributes in PATCHES.items():
        for attr_name, attr_value in attributes.items():
            patch_module(module, attr_name, attr_value)

    # Step 2: Dynamic patching of all already loaded modules
    for name, module in sys.modules.items():
        if (
            name.startswith("ethereum")
            or name.startswith("mpt")
            or name.startswith("keth")
            or name.startswith("cairo")
        ):
            for attr_name, attr_value in all_attrs.items():
                patch_module(module, attr_name, attr_value)


# Apply patches immediately when the module is imported
apply_patches()
