# AI-Reports

## AI-REPORT: Memory Management for pytest-xdist Workers (June 3, 2025)

### Problem

CI jobs were crashing with "node down: Not properly terminated" errors when
running pytest-xdist with high parallelism (48 workers for EF tests). Memory
exhaustion during test execution caused worker processes to crash, interrupting
the test suite.

### Solution

Implemented a simple hook-based memory management system that pauses test
execution when memory is insufficient:

1. **Pre-Test Memory Check**: Added `pytest_runtest_setup` hook that checks
   available memory before each test runs
2. **Automatic Pausing**: When memory is low, test execution pauses until
   sufficient memory becomes available
3. **Environment-Aware Thresholds**: Different memory requirements for CI (3GB
   free, max 90% usage) vs local development (1GB free, max 90% usage)
4. **Zero Configuration**: Works out of the box with automatic CI detection

### Implementation

- **`memory_manager.py`**: Simple utilities with `wait_for_memory()` function
  and environment detection
- **`hooks.py`**: Added memory check in `pytest_runtest_setup` hook before each
  test
- **`pyproject.toml`**: Added `psutil>=6.1.0` dependency for memory monitoring

### Key Features

- **Non-intrusive**: No changes to worker counts or pytest-xdist configuration
- **Automatic Recovery**: Workers resume when memory becomes available
- **Timeout Protection**: Tests fail gracefully if memory doesn't become
  available within timeout (2 minutes CI, 2 minutes local)
- **Configurable**: CLI options for custom thresholds
  (`--min-available-memory-gb`, `--max-memory-percent`,
  `--disable-memory-management`)

### Impact

Prevents CI crashes while maintaining maximum parallelism. Workers automatically
pause/resume based on memory availability, eliminating "node down" errors
without reducing test concurrency.

## AI-REPORT: Cairo PIE Support and AR Inputs Generation for External Users (May 30, 2025)

### Context & Motivation

As Keth integrates with external partners like SHARP for Applicative Recursion
(AR) workflows, we needed to provide an easy-to-use CLI interface that allows
external users to test Keth efficiently. SHARP is currently working with Cairo
PIE files until STWO integrates SHARP, transitioning to prover input formats.

### Implementation: Cairo PIE Support

#### 1. **Rust Bindings Enhancement (`crates/cairo-addons/src/vm/runner.rs`)**

- **New Parameter**: Added `cairo_pie: bool` parameter to the `generate_trace`
  function
- **Execution Mode Logic**: Modified `prepare_cairo_execution` to handle two
  distinct modes:
  - **Proof Mode** (`proof_mode=true`, `cairo_pie=false`): Optimized for STWO
    proving with trace padding and strict builtin requirements
  - **Cairo PIE Mode** (`proof_mode=false`, `cairo_pie=true`): Generates Cairo
    PIE files for SHARP STONE compatibility
- **Mutual Exclusivity**: Added validation to prevent simultaneous use of proof
  mode and Cairo PIE mode, as they have incompatible requirements.
- **Output Handling**:
  - Cairo PIE files are written using `cairo_pie_result.write_zip_file()` as ZIP
    archives
  - Prover input files continue as JSON/binary format

#### 2. **Python CLI Integration (`cairo/scripts/keth.py`)**

- **New Parameter**: Added `--cairo-pie` flag to both `trace` and
  `generate_ar_inputs` commands
- **Filename Pattern**: Implemented consistent naming convention:
  - **Cairo PIE**: `cairo_pie_{block}_{step}_{args}.zip`
  - **Prover Input**: `prover_input_info_{block}_{step}_{args}.json`
- **StepHandler Enhancement**: Updated `get_output_filename()` to generate
  appropriate filenames based on output type

### Implementation: AR Inputs Generation Command

#### **New Command: `generate_ar_inputs`**

This command provides a one-stop solution for generating all traces related to a
block:

1. **Automated Step Execution**: Runs `generate_trace` for each required step:

   - `init` step
   - `body` steps (chunked by configurable `--body-chunk-size`, default 10
     transactions)
   - `teardown` step

2. **Consistent Naming**: Ensures prover input/Cairo PIE naming follows the
   established pattern:

   - Init: `{type}_{block}_init.{ext}`
   - Body: `{type}_{block}_body_{start}_{len}.{ext}`
   - Teardown: `{type}_{block}_teardown.{ext}`

3. **Flexible Output**: Supports both Cairo PIE (with `--cairo-pie`) and prover
   input formats

4. **Smart Chunking**: Automatically determines the number of body chunks based
   on total transactions and chunk size

### Impact & Benefits

#### **For External Partners**

- **Single Command**: Generate all required traces with one command
- **SHARP Compatibility**: Cairo PIE support until STWO integration
- **Easy Testing**: Simplified workflow for external validation

#### **For Keth Development**

- **Modular Design**: Clean separation between proof and PIE modes
- **Consistent Interface**: Uniform naming and parameter patterns
- **Future-Proof**: Ready for STWO transition while maintaining SHARP support

### Technical Decisions

#### **Why Mutual Exclusivity?**

Proof mode and Cairo PIE mode have fundamentally different requirements:

- **Proof mode** needs trace padding and strict validation for STWO proving
- **Cairo PIE mode** requires relaxed settings for SHARP compatibility

#### **Why ZIP Format for Cairo PIE?**

Cairo PIE files use the ZIP format as specified by the Cairo VM's
`write_zip_file()` method, maintaining compatibility with existing SHARP
infrastructure.

## AI-REPORT: Fix State Compatibility for EELS in Teardown Tests (May 3, 2025)

### Problem

A test failure occurred, particularly noticeable with the
`test_data/22615247.json` fixture, during the execution of the EELS `apply_body`
function within the Python `load_teardown_input` utility
(`cairo/utils/fixture_loader.py`). The issue stemmed from a mismatch between
Keth's internal `State` representation and the format expected by EELS:

1.  Keth's ZKPI loading and internal Python `State` object use `None` to
    represent accounts or storage slots that are absent or empty after being
    touched in a transaction - the reason being that any key accessed during the
    Cairo execution **must** appear in the python object.
2.  The EELS `apply_body` function expects such absent entries to be entirely
    missing from the state trie data structures, not represented as `None`. It
    also expects specific representations for zero/empty values (e.g., `b""` for
    code). Passing a `State` object containing `None` values directly to EELS
    `apply_body` led to incorrect execution or errors (like gas inconsistencies
    or `InvalidBlock` exceptions in direct EELS calls).

### Solution

The fix involved ensuring the `State` object is formatted correctly before being
passed to EELS `apply_body` and handling the ZKPI representation consistently:

1.  **Consistent ZKPI Loading**: Updated `mpt.ethereum_tries.PreState.from_data`
    to correctly interpret storage values of `0` from the ZKPI data as `None` in
    the Python `Trie` structure, representing absence/nullity in the pre-state,
    aligning with the April 22 changes.
2.  **EELS State Formatting**: Introduced a new utility function
    `format_state_for_eels` in `cairo/utils/fixture_loader.py`. This function
    cleans the `State` object by:
    - Removing account entries where the value is `None`.
    - Setting `code` to `b""` for accounts where it's `None`.
    - Removing storage entries where the value is `None`.
    - Removing entire storage tries if they become empty after cleaning.
3.  **Applying Formatting**: Modified `prepare_body_input` and
    `load_teardown_input` to call `format_state_for_eels` on the `State` object
    _before_ passing it to EELS functions like `apply_body`.
4.  **State Restoration**: Ensured that `load_teardown_input` correctly restores
    the `None` representations back into the `State` object _after_ the
    `apply_body` call, maintaining consistency with Keth's internal logic for
    subsequent steps (like teardown).
5.  **Testing**: Added `test_data/22615247.json` to `test_teardown.py` and
    introduced `test_e2e_eels` in `test_e2e.py` to specifically test EELS
    compatibility and verify gas calculations even when full state root
    verification fails due to partial ZKPI state.

### Impact

This change ensures that the `State` object passed to EELS functions conforms to
its expected format, resolving errors previously encountered during the Python
execution phase of teardown tests. It correctly handles the distinction between
absent/null values (`None` in Keth Python) and zero values (`U256(0)`, empty
accounts) when interacting with EELS.

## AI-REPORT: New Cairo Program Proving Script (May 2, 2025)

### Overview

A new script, `prove_cairo.py`, has been added to the Keth project under
`cairo/scripts/`. This script is designed to be an unopinionated tool focused on
a single feature: running and proving any compiled Cairo program, independent of
Keth-specific logic. This addition enhances the flexibility of the proving
toolchain by allowing users to work with arbitrary Cairo programs, which might
be useful for testing and development purposes.

### What Was Done

- **New Script Creation**: Created `prove_cairo.py` as a standalone CLI tool
  using the Typer framework for command-line interface development.
- **Integration with Existing Bindings**: Utilized existing Rust bindings from
  `cairo_addons.rust_bindings` for trace generation (`run_generate_trace`),
  proof generation (`run_prove`), and verification (`run_verify`).
- **Feature Implementation**: Implemented a single command `run_and_prove` that
  handles running a compiled Cairo program, generating a proof with STWO, and
  optionally verifying the proof.
- **Support for Cairo-Compatible Serialization**: Added support for serializing
  proofs to a Cairo-compatible format using the `--serde-cairo` flag, aligning
  with features in `keth.py`.
- **Performance Improvements**: Used a CanonicalWithoutPedersen preprocessed
  trace variant when using `prove_cairo`, which is faster to setup. We don't
  need proving of pedersen hashes.

### Why It Was Done

- **Flexibility**: To provide a tool that can run and prove any Cairo program,
  not just those related to Ethereum block processing as in `keth.py`. This
  allows developers to use the STWO proving system for a broader range of
  applications.
- **Simplification**: To offer a focused, unopinionated interface that avoids
  the complexity and specific assumptions baked into the Keth workflow, making
  it easier for users to integrate with custom Cairo projects.

### How to Use the New Script

The `prove_cairo.py` script can be invoked from the command line with the
following options:

- **Command**: `run_and_prove`
- **Options**:
  - `--compiled-program <PROGRAM_PATH>`: (Required) Path to the compiled Cairo
    program to run and prove.
  - `--entrypoint <ENTRYPOINT>`: (Default: "main") The entrypoint function name
    to execute in the program.
  - `--arguments <ARGUMENTS>`: (Default: "") Serialized arguments as
    comma-separated felts for the program.
  - `--output-dir <OUTPUT_DIR>`: (Default: "output") Directory to save trace
    artifacts and the generated proof.
  - `--serde-cairo`: (Default: False) Serialize the proof to a Cairo-compatible
    format.
  - `--verify`: (Default: False) Verify the proof after generation.

**Example Usage**:

```bash
uv run prove_cairo --compiled-program build/my_program_compiled.json --entrypoint main --arguments "1,2,3" --output-dir output --serde-cairo --verify
```

This command runs the specified Cairo program, generates a proof, saves
artifacts to the `output` directory, serializes the proof in Cairo-compatible
format, and verifies the proof.

## AI-REPORT: State Root Restoration and Hash Function Abstraction (April 23, 2025)

### Context & Goal

Following the previous refactor (see AI-REPORT April 11, 2025) that moved to a
diff-based state validation aligned with EELS, this change restores the
capability to compute the full `state_root` and `storage_root` directly within
Keth. The primary goal is for the MPT `root` function to support multiple
cryptographic hash functions (Keccak for final roots, Blake2s for intermediate
in our applicative-recursion commitments, and eventually Poseidon later) for
these computations, bringing better flexibility.

### Implementation: Hash Function Abstraction

The core challenge is abstracting the hash function used within the `root`
computation (for the main state trie) and the `storage_roots` computation (for
individual account storage tries). Cairo's language design makes traditional
dynamic dispatch or passing function closures complex (functions take different
arguments, we can only `call abs` on the function label, etc.)

**Pattern Chosen**: We use implicit arguments to manage hash function selection
and execution:

1.  **Builtin Pointers**: Functions supporting multiple hashing functions now
    include implicit arguments for all potentially needed hash builtins (e.g.,
    `keccak_ptr`, `poseidon_ptr`). This ensures that regardless of the function
    chosen at runtime, we have the right segments available.
2.  **Hash Function Identifier & Dispatch**: The actual hash computation is
    delegated to a central `hash_with` function (located in
    `cairo/ethereum/crypto/hash.cairo`). This function takes an explicit
    `hash_function_name: felt` argument (e.g., `'keccak256'`, `'blake2s'`) which
    identifies the desired hash algorithm. Inside `hash_with`, conditional logic
    uses this name to select the appropriate hash implementation (e.g., `keccak`
    or `blake2s`) and use the corresponding implicit builtin pointers (like
    `keccak_ptr`, if used). This approach avoids the complexity of using
    `call abs` with function labels, which would require branching to manage the
    differing implicit arguments required by each hash function. Functions like
    `root`, `state_root` or `storage_roots` propagate the necessary builtins and
    the `hash_function_name` down to where `hash_with` is called.
3.  **Hash-Specific Constants**: Constants like `EMPTY_ROOT` and `EMPTY_HASH`
    were renamed to `EMPTY_ROOT_KECCAK` and `EMPTY_HASH_KECCAK` to distinguish
    them, as different hash functions have different default empty values.
4.  We use the newly introduced opcode in the VM and proven by STWO to compute
    Blake2s hashes (see cairo_core.hash.blake2s)

### Changes

- **`state.cairo`**: Re-implemented `state_root` and introduced `storage_roots`
  and helper functions. These functions now include implicit arguments for
  various hash builtins (`poseidon_ptr`, `keccak_ptr` where relevant). They will
  be used to compute intermediate state roots (with blake2s) when splitting our
  state transition into chunks.
- **`fork_types.cairo`, `state.cairo`**: Renamed `EMPTY_ROOT`/`EMPTY_HASH` to
  `EMPTY_ROOT_KECCAK`/`EMPTY_HASH_KECCAK`.

### Implications

The hash abstraction pattern prepares the codebase for using alternative hash
functions like Blake2s, more efficient than Poseidon-F252, for future features
like intermediate state commitments.

## AI-REPORT: Differentiating Null and Zero in State/Storage Diffs (April 22, 2025)

### Problem

Previously, the system did not consistently differentiate between a storage slot
holding the value `U256(0)` and a storage slot that was genuinely empty (absent
from the state, represented as `null`). This ambiguity stemmed from:

1.  The ZK Proven Input (ZKPI) format providing `0` for storage slots that were
    touched but ultimately empty post-transaction, rather than indicating
    absence.
2.  The Cairo hashing logic for state/storage diffs (`hash_state_storage_diff`,
    `poseidon_storage_diff`) implicitly treated null pointers (representing
    absence in `args_gen` output) as `U256(0)` during hashing.
3.  The Python type system and `args_gen.py` did not explicitly model
    optionality for storage values, leading to potential inconsistencies during
    serialization.

This could lead to having two identical state diff commitments for different
tries, as the storage diffs would be the same, and the account diffs would be
the same, but the nodes could be present / absent in the tries.

### Solution

This update introduces changes to correctly distinguish between null/absent
values and the zero value (`U256(0)`) throughout the diffing and hashing
process:

1.  **Explicit Optional Type**: Introduced `OptionalU256` struct in
    `cairo-core/numeric.cairo` and corresponding `Optional[U256]` type hint in
    Python (`keth_types`, `args_gen`). This allows explicit representation of
    potentially absent storage values.
2.  **ZKPI Interpretation**: Modified `mpt.ethereum_tries.PreState.from_zkpi` to
    interpret storage values of `0` from the ZKPI data as `None` (representing
    absence) when populating the initial Python `Trie` structure. This correctly
    reflects the intended state before serialization.
3.  **Serialization (`args_gen.py`)**: Updated `generate_state_arg` and
    `generate_transient_storage_arg` to handle `Trie[..., Optional[U256]]`. Now,
    Python `None` values in the storage trie are serialized to Cairo's
    `OptionalU256` type, likely resulting in null pointers for absent values,
    distinct from a pointer to `U256(0)`.
4.  **Hashing Logic (`hash_diff.cairo`)**:
    - Refactored `poseidon_storage_diff` and
      `_accumulate_state_storage_diff_hashes` to work with `OptionalU256`. They
      now conditionally include value components in the hash based on whether
      the pointer is null, correctly hashing absence differently from `U256(0)`.
      The implicit conversion of null to `U256(0)` was removed.
    - Updated `poseidon_account_diff` to handle cases where the `new_value`
      account might be null.
5.  **Comparison**: Added `OptionalU256__eq__` in Cairo and corresponding tests
    to compare these optional values correctly. Added null pointer checks to
    `is_ptr_equal`.

### Impact

These changes ensure that the Poseidon hashes generated for state and storage
diffs accurately reflect the distinction between zero values and absent entries.
This enhances the correctness of the state transition verification based on diff
commitments. Tests were added/updated to cover the new optional types and
comparison logic.

## AI-REPORT: Passing Objects in our Python Cairo Runner and the Rust CairoVM

**Runner Strategy**: Keth uses a dual approach to executing Cairo: a backend in
Rust - i.e. the Rust CairoVM to run Cairo programs, 10x faster than the Python
CairoVM - and a frontend in Python (test framework, serialization tools, type
system equivalent to EELS).

- **Exposing Rust functionality in Python frontend**: PyO3 bindings expose Rust
  functionality to Python in `runner.rs`
- **Passing Python objects in Rust**: The system uses execution scopes
  (exec_scopes) as a persistent store where Python objects (like program
  identifiers and input data) are accessible during hint execution in
  `runner.py`, `injected.py` and `hints.py`.

The file `runner.py` serves as the orchestration layer for Cairo program
execution, implementing two parallel execution paths: `run_python_vm` (for Cairo
runs using the CairoVM Python) and `run_rust_vm` (uses the faster CairoVM Rust).
It handles the complete execution lifecycle including:

1. Program selection and entrypoint metadata preparation
1. Memory segment initialization and builtin runner configuration
1. Argument serialization from Python types to Cairo memory representation
1. Stack construction with builtin pointers and program arguments
1. VM configuration, program loading, and execution with resource constraints
1. Post-execution operations (verification, relocation, trace collection)
1. Return value deserialization from Cairo memory back to Python objects
1. Diagnostic output generation (traces, memory dumps, profiling data)

## AI-REPORT: Dict Squashing Verification Mechanism (April 20, 2025)

**Dict Squashing Soundness**: To ensure all dictionaries are properly squashed
during block proving, we've implemented a verification mechanism in our CairoVM
runner.

- **Debugging Process**: Added `attach_name` hints in Cairo code to label
  dictionaries, aiding in tracking and debugging squashing status. e.g:
  attaching the name 'transactions' to the dict for the transactions trie:

```cairo
    let (transaction_ptr) = default_dict_new(0);
    tempvar dict_ptr = transaction_ptr;
    tempvar name = 'transactions';
    %{ attach_name %}
```

- **Verification Logic**: In the CairoVM repo, `DictTracker` now includes
  `is_squashed` (initialized `True`) and `name` fields (to make debugging
  easier). Mutations (`get_value`, `insert_value`) set `is_squashed` to `False`,
  and we modified our `dict_squash` function hint to explicitly set it to
  `True`. As such ALL dict squash / finalizing must be done through our
  `dict_squash` function (or our own default_dict_finalize) - in
  `legacy.utils.dict`.
- **End-to-End Check**: Tests in `test_main.py` use `cairo_run` with
  `check_squashed_dicts=True` to verify all dicts are squashed post-execution,
  ensuring soundness during proving.

This mechanism helps catching unsquashed dicts are caught during testing,
ensuring our usage of dicts is sound.

## AI-REPORT: Typing Module Union Order Issue (April 15, 2025)

### Issue with Typing Module

**Issue**: The Python `typing` module caches the order of types in a `Union`
when first encountered, causing all permutations to follow the same order,
leading to inconsistencies in type handling.

**Cause**: This occurs due to internal caching in the `typing` module, notably
affecting Keth's type system where EELS uses both
`Union[Bytes, LegacyTransaction]` and `Union[LegacyTransaction, Bytes]`, while
Keth standardizes on the former.

**Solution**: Clearing the `typing` module's cache by invoking functions in
`typing._cleanups` resets the order, ensuring consistent type handling. This
workaround is implemented in `args_gen.py`.

## AI-REPORT: Custom Types and Patching EELS Imports (April 14, 2025)

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

Patching is centralized in `keth_types.patches`, which defines a `PATCHES`
dictionary mapping attribute names to Keth's custom types. Importing
`keth_types.patches` triggers `apply_patches()`, which iterates through all
sub-modules of the `ethereum` package and `mpt` modules in `sys.modules`, using
`setattr` to override original definitions with custom types. This approach
ensures that patches are applied automatically to all relevant modules,
regardless of loading order. If we had only patched in the module where items
are defined, we'd get some errors, as these modules were already loaded in
python's module system, and the patches would not be effective everywhere.

### Challenges with Python Module Loading

Python's module loading order poses a challenge. Modules are cached in
`sys.modules`, and if EELS modules (e.g., `ethereum.prague.vm`) load before
patches, original types are used instead of Keth's. This did happen because of
pytest plugins that initialized earlier than `conftest.py` hooks.

### Proper Patching Methodology

To ensure consistent patch application, follow these guidelines:

- **Early Import**: Import `keth_types.patches` at the start of every entry
  point (e.g., `prove_block.py`, `conftest.py`) before EELS modules to avoid
  unpatched cached modules.
- **Custom Pytest Plugin (if needed)**: Because pytest plugins load EELS modules
  early, we created a plugin (see `pyproject.toml`) to apply patches during
  plugin init, ensuring it runs before, for example, hypothesis strategies.
- **Centralized Type Definitions**: Define all custom types in
  `keth_types.types` as a single source of truth for imports.

These practices ensure consistent use of custom types, preventing discrepancies
between Python and Cairo logic. Maintainers should audit entry points for patch
imports and extend `PATCHES` in `keth_types.patches` for new attributes or
types.

## AI-REPORT: Ethereum State Diff Comparison Logic PR (April 11, 2025)

### Overview

This PR refactors the Ethereum state transition prover in Cairo, replacing final
`state_root` validation with a diff-based approach. It verifies state
modifications (account/storage diffs) from the State Transition Function (STF)
against Merkle Patricia Trie (MPT) diffs, enhancing modularity and altering the
prover's input/output contract.

### Context

The system proves Ethereum block state transitions. Previously, it validated by
recomputing the post-state root and comparing it to the block header's
`state_root`. This PR adopts an EELS-aligned strategy, validating STF-generated
diffs (account/storage changes) against MPT diffs computed from provided
`pre_state_root` and `post_state_root`, avoiding costly full state root
recalculation.

### Changes

1. **cairo/ethereum/prague/main.cairo (Entrypoint)**

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

2. **cairo/ethereum/prague/fork.cairo (STF)**

   - **Change**: Removed `state_root` equality check
     (`output.value.state_root == block.value.header.value.state_root`).
   - **Comment**: Notes validation now uses diff comparison, per EELS.
   - **Rationale**: Avoids redundant root computation, relying on diff-based
     correctness.

3. **cairo/ethereum/prague/fork_types.cairo (Data Structures)**

   - **New Function**: `account_eq_without_storage_root` compares
     `OptionalAccount` instances, ignoring `storage_root`.
   - **Update**: `Account__eq__` uses this helper.
   - **Rationale**: Separates account (nonce, balance, code hash) and storage
     diffs for independent validation, as storage changes are tracked
     separately.

4. **cairo/ethereum/prague/state.cairo (State Management)**

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

6. **cairo/tests/ef_tests/prague/test_state_transition.py (Tests)**

   - **Change**: Ignores `wrongStateRoot_Prague` test, obsolete due to
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

### Patterns

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

### Side Effects and Risks

- **API Change**: `main` requires MPT context inputs, outputs diff commitments.
- **Input Dependency**: Relies on external `node_store`, preimages,
  `post_state_root`. Validation critical (e.g., well-formed tries, correct node
  mappings).
- **Testing Shift**: Obsoletes state root tests; needs new diff-focused tests.
- **Performance**: Avoids STF root hashing but adds MPT diff computation and
  Poseidon hashing costs. Requires benchmarking.
- **Complexity**: MPT diff generation adds complexity, though STF logic is
  simplified.

### Decisions

- **Why Diff Comparison?**
  - **Modularity**: Decouples STF from MPT root calculation.
  - **Efficiency**: Avoids costly MPT hashing in Cairo STF.
  - **Verifiability**: Enables incremental proofs for transaction chunks.
- **Why Ignore Storage Root?** Treats account and storage changes as separate
  streams for distinct hashing.
- **Why Remove Python Recalculation?** Validation uses input `post_state_root`
  for MPT diffs, not STF recomputation.
