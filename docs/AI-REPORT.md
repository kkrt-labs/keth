# AI-REPORT: Ethereum State Diff Comparison Logic PR (April 11, 2025)

## Overview

This PR refactors the Ethereum state transition prover in Cairo, replacing final
`state_root` validation with a diff-based approach. It verifies state
modifications (account/storage diffs) from the State Transition Function (STF)
against Merkle Patricia Trie (MPT) diffs, enhancing modularity and altering the
prover's input/output contract.

## Context

The system proves Ethereum block state transitions. Previously, it validated by
recomputing the post-state root and comparing it to the block header's
`state_root`. This PR adopts an EELS-aligned strategy, validating STF-generated
diffs (account/storage changes) against MPT diffs computed from provided
`pre_state_root` and `post_state_root`, avoiding costly full state root
recalculation.

## Changes

1. **cairo/ethereum/cancun/main.cairo (Entrypoint)**

   - **Logic Shift**: Orchestrates diff comparison:
     - Runs STF (`state_transition`) to generate account/storage diffs.
     - Computes MPT diffs (`compute_diff_entrypoint`) using `pre_state_root`
       (parent block) and input `post_state_root`.
     - Sorts diffs (`sort_account_diff`, `sort_storage_diff`).
     - Computes Poseidon hash commitments for STF diffs
       (`hash_state_account_diff`, `hash_state_storage_diff`) and MPT diffs
       (`hash_account_diff_segment`, `hash_storage_diff_segment`).
     - Asserts commitment equality
       (`state_account_diff_commitment == trie_account_diff_commitment`,
       `state_storage_diff_commitment == trie_storage_diff_commitment`).
   - **I/O Changes**:
     - **Inputs**: Added `node_store`, `address_preimages`,
       `storage_key_preimages`, `post_state_root` via `%{ main_inputs %}` hint.
     - **Outputs**: Removed `post_state_root`, `block_hash`. Now outputs
       `pre_state_root`, STF/MPT diff commitments (6 felts, down from 8).
   - **Rationale**: Validates state changes incrementally, reducing STF
     complexity by offloading root hash computation.

2. **cairo/ethereum/cancun/fork.cairo (STF)**

   - **Change**: Removed `state_root` equality check
     (`output.value.state_root == block.value.header.value.state_root`).
   - **Comment**: Notes validation now uses diff comparison, per EELS.
   - **Rationale**: Avoids redundant root computation, relying on diff-based
     correctness.

3. **cairo/ethereum/cancun/fork_types.cairo (Data Structures)**

   - **New Function**: `account_eq_without_storage_root` compares
     `OptionalAccount` instances, ignoring `storage_root`.
   - **Update**: `Account__eq__` uses this helper.
   - **Rationale**: Separates account (nonce, balance, code hash) and storage
     diffs for independent validation, as storage changes are tracked
     separately.

4. **cairo/ethereum/cancun/state.cairo (State Management)**

   - **Change**: Replaced `default_dict_finalize` with `dict_squash` in
     `finalize_state` for `main_trie` and `storage_tries`.
   - **Rationale**: Preserves pre-execution values in state tries (not
     defaulting to 0), ensuring accurate diff computation.

5. **cairo/scripts/prove_block.py (Proving Script)**

   - **Changes**:
     - Uses `ZkPi.from_data` to load inputs, including `transition_db` (MPT
       data).
     - Supplies `node_store`, preimages, `post_state_root` to Cairo
       (`program_input`).
     - Replaces `prepare_state_and_code_hashes` with `map_code_hashes_to_code`
       (no more adaptation of the State object required: it must _always_ be
       made upfront).
     - Removed Python state root recalculation (`apply_body`), as
       `post_state_root` is now an input of the program.
     - Patches Python environment: adds `is_account_alive`, `EMPTY_ACCOUNT`.
   - **Rationale**: Aligns with diff-based validation, simplifies input
     preparation, ensures Python-Cairo consistency. We want the pre-state to be
     loaded from zkpi, which contains all touched accounts / storage slots.

6. **cairo/tests/ef_tests/cancun/test_state_transition.py (Tests)**

   - **Change**: Ignores `wrongStateRoot_Cancun` test, obsolete due to
     diff-based validation;
   - **Rationale**: Tests focusing on state root mismatches are irrelevant as we
     don't recompute a new state root, we don't need to test for it: our
     diff-approach is sufficient.

7. **mpt/hash_diff.cairo (Diff Hashing)**

   - **Change**: Skips unchanged diffs in `hash_state_account_diff` and
     `hash_state_storage_diff` using `account_eq_without_storage_root` and
     `U256__eq__`. Handles null pointers as `U256::ZERO` for storage diffs.
   - **Rationale**: excluding no-diff entries from the hash computation aligns
     STF and MPT diff commitments.

8. **mpt/trie_diff.cairo (Trie Diffs)**

   - **Change**: Skips account diffs if only `storage_root` differs
     (`account_eq_without_storage_root`). Skips storage diffs if values are
     equal (`U256__eq__`).
   - **Rationale**: We don't recompute the storage root in the STF. We ensure we
     have the correct result by emitting full storage diffs.

9. **Python and Test Updates**
   - **trie_diff.py**: Filters out unchanged storage diffs
     (`left_decoded == right_decoded`). Computes commitments for testing.
   - **test_main.py**: Verifies commitments match expected values.
   - **args_gen.py**: Patches `is_account_alive` to check that it's not the
     EMPTY_ACCOUNT (with storage_root and code_hash) instead of only checking
     nonce, balance, code.
   - **Rationale**: Enhances test coverage for diff-based logic, aligns Python
     logic with Cairo.

## Custom Types and Patching EELS Imports (April 14, 2025)

### Why Custom Types and Patching?

Keth's Cairo-based prover requires custom types to ensure compatibility with the
Ethereum EELS library. EELS types are incompatible with Cairo's data structures
and serialization needs for zero-knowledge proof generation. Keth's custom types
(e.g., `Account`, `Evm`, `Message`) override EELS defaults, adjusting equality
comparisons (e.g., ignoring `storage_root` in `Account`) and serialization to
match Cairo's expectations.

Patching replaces EELS's original types with Keth's custom types across the
Python codebase. This prevents inconsistencies between Python logic (for input
prep and testing) and Cairo logic (for proving).

### How Patching Works

Patching is centralized in `keth_types.patches`, which maps EELS and MPT modules
to Keth's custom types in a `PATCHES` dictionary. Importing `keth_types.patches`
triggers `apply_patches()`, using `setattr` to override original definitions in
modules like `ethereum.cancun.fork_types`. This avoids scattered `setattr`
calls, enhancing maintainability.

### Challenges with Python Module Loading

Python's module loading order poses a challenge. Modules are cached in
`sys.modules`, and if EELS modules (e.g., `ethereum.cancun.vm`) load before
patches, original types are used instead of Keth's. This is common with pytest
plugins that initialize early, before `conftest.py` hooks.

### Proper Patching Methodology

To ensure consistent patch application, follow these guidelines:

- **Early Import**: Import `keth_types.patches` at the start of every entry
  point (e.g., `prove_block.py`, `conftest.py`) before EELS modules to avoid
  unpatched cached modules.
- **Custom Pytest Plugin (if needed)**: Because pytest plugins load EELS modules
  early, we created a plugin (see `pyproject.toml`) to apply patches during
  plugin init.
- **Centralized Type Definitions**: Define all custom types in
  `keth_types.types` as a single source of truth for imports.

These practices ensure consistent use of custom types, preventing discrepancies
between Python and Cairo logic. Maintainers should audit entry points for patch
imports and extend `PATCHES` in `keth_types.patches` for new modules or types.

## Patterns

- **Diff-Based Validation**: Verifies correctness via STF vs. MPT diff
  comparison, not final state root.
- **Input-Driven Post-State**: `post_state_root` is input, not computed,
  shifting validation dependency.
- **Account vs. Storage Separation**: `account_eq_without_storage_root` isolates
  account and storage diffs for independent hashing.
- **Differential Diff Handling**:
  - **MPT Diffs**: Omits unchanged slots/accounts (ignoring `storage_root`).
  - **STF Diffs**: Cairo dictionaries capture all accesses; unchanged entries
    skipped during commitment (`hash_state_account_diff`,
    `hash_state_storage_diff`).
- **Optimized Comparison**: Uses pointer comparison first for accounts, falling
  back to field-by-field if inconclusive.
- **Python Patching**: Consistent `setattr` in `prove_block.py` aligns Python
  and Cairo behaviors.

The most important pattern to keep in mind is that **default_dicts get
serialized as default_dict** meaning that we can query absent keys, while
**non-default_dicts** in args_gen generate regular dicts. As such one must be
very careful when writing tests: if you don't know all keys queried during the
test, you **must** use default_dicts.

## Side Effects and Risks

- **API Change**: `main` requires MPT context inputs, outputs diff commitments.
- **Input Dependency**: Relies on external `node_store`, preimages,
  `post_state_root`. Validation critical (e.g., well-formed tries, correct node
  mappings).
- **Testing Shift**: Obsoletes state root tests; needs new diff-focused tests.
- **Performance**: Avoids STF root hashing but adds MPT diff computation and
  Poseidon hashing costs. Requires benchmarking.
- **Complexity**: MPT diff generation adds complexity, though STF logic is
  simplified.

## Decisions

- **Why Diff Comparison?**
  - **Modularity**: Decouples STF from MPT root calculation.
  - **Efficiency**: Avoids costly MPT hashing in Cairo STF.
  - **Verifiability**: Enables incremental proofs for transaction chunks.
- **Why Ignore Storage Root?** Treats account and storage changes as separate
  streams for distinct hashing.
- **Why Remove Python Recalculation?** Validation uses input `post_state_root`
  for MPT diffs, not STF recomputation.
