import json
from functools import partial
from pathlib import Path
from typing import Dict

import pytest

from tests.ef_tests.helpers import EEST_TESTS_PATH, ETHEREUM_TESTS_PATH
from tests.ef_tests.helpers.load_state_tests import (
    fetch_state_test_files,
    idfn,
    run_blockchain_st_test,
)
from utils.fixture_loader import LoadKethFixture

pytestmark = [
    pytest.mark.cairo_file(f"{Path().cwd()}/cairo/ethereum/cancun/fork.cairo"),
    pytest.mark.max_steps(100_000_000),
]

fetch_cancun_tests = partial(fetch_state_test_files, network="Cancun")


ETHEREUM_BLOCKCHAIN_TESTS_DIR = f"{ETHEREUM_TESTS_PATH}/BlockchainTests/"
EEST_BLOCKCHAIN_TESTS_DIR = f"{EEST_TESTS_PATH}/blockchain_tests/"

NETWORK = "Cancun"
PACKAGE = "cancun"

SLOW_TESTS = (
    # GeneralStateTests
    "stTimeConsuming/CALLBlake2f_MaxRounds.json",
    "stTimeConsuming/static_Call50000_sha256.json",
    "vmPerformance/loopExp.json",
    "vmPerformance/loopMul.json",
    "QuadraticComplexitySolidity_CallDataCopy_d0g1v0_Cancun",
    "CALLBlake2f_d9g0v0_Cancun",
    "CALLCODEBlake2f_d9g0v0",
    # GeneralStateTests
    "stRandom/randomStatetest177.json",
    "stCreateTest/CreateOOGafterMaxCodesize.json",
    # ValidBlockTest
    "bcExploitTest/DelegateCallSpam.json",
    # InvalidBlockTest
    "bcUncleHeaderValidity/nonceWrong.json",
    "bcUncleHeaderValidity/wrongMixHash.json",
    # Big loops
    "stStaticCall/static_LoopCallsThenRevert.json",
    "stStaticCall/static_LoopCallsDepthThenRevert.json",
    "stStaticCall/static_LoopCallsDepthThenRevert2.json",
    "stStaticCall/static_LoopCallsDepthThenRevert3.json",
    "stStaticCall/LoopDelegateCallsDepthThenRevertFiller.json",
    # Lots of transactions / blocks
    "bcWalletTest/walletReorganizeOwners.json",
)

# These are tests that are considered to be incorrect,
# Please provide an explanation when adding entries
IGNORE_TESTS = (
    # ValidBlockTest
    "bcForkStressTest/ForkStressTest.json",
    "bcGasPricerTest/RPC_API_Test.json",
    "bcMultiChainTest",
    "bcTotalDifficultyTest",
    # InvalidBlockTest
    "bcForgedTest",
    "bcMultiChainTest",
    "GasLimitHigherThan2p63m1_Cancun",
    # Tests on state root - we don't implement state root computations in our approach
    "wrongCoinbase_Cancun",
    "wrongStateRoot_Cancun",
    # Tests of modexp with big header / base sizes. We reject any header / base length above 48 bytes
    "modexp-fork_Cancun-d30g3v0",
    "modexp-fork_Cancun-d29g3v0",
    "modexp-fork_Cancun-d29g2v0",
    "modexp-fork_Cancun-d28g0v0",
    "modexp-fork_Cancun-d2g0v0",
    "modexp-fork_Cancun-d27g1v0",
    "modexp-fork_Cancun-d27g2v0",
    "modexp-fork_Cancun-d36g3v0",
    "modexp-fork_Cancun-d28g2v0",
    "modexpRandomInput-fork_Cancun-d0g0v0",
    "modexp_modsize0_returndatasize-fork_Cancun-d4g0v0",
    "modexp-fork_Cancun-d2g1v0",
    "modexp-fork_Cancun-d27g3v0",
    "modexp-fork_Cancun-d30g1v0",
    "modexp-fork_Cancun-d28g1v0",
    "modexp-fork_Cancun-d29g1v0",
    "modexp-fork_Cancun-d27g0v0",
    "modexp_modsize0_returndatasize-fork_Cancun-d3g0v0",
    "modexp-fork_Cancun-d37g0v0",
    "modexp-fork_Cancun-d2g2v0",
    "modexp-fork_Cancun-d37g1v0",
    "randomStatetest650-fork_Cancun-d0g0v0",
    "modexp-fork_Cancun-d37g3v0",
    "modexpRandomInput-fork_Cancun-d0g1v0",
    "modexp-fork_Cancun-d36g0v0",
    "modexpRandomInput-fork_Cancun-d1g1v0",
    "modexpRandomInput-fork_Cancun-d1g0v0",
    "modexpRandomInput-fork_Cancun-d2g0v0",
    "modexp-fork_Cancun-d30g2v0",
    "modexp-fork_Cancun-d30g0v0",
    "modexp-fork_Cancun-d28g3v0",
    "modexp-fork_Cancun-d36g2v0",
    "modexp_modsize0_returndatasize-fork_Cancun-d2g0v0",
    "modexp-fork_Cancun-d2g3v0",
    "modexp-fork_Cancun-d37g2v0",
    "modexp-fork_Cancun-d29g0v0",
    "modexp-fork_Cancun-d36g1v0",
    "modexpRandomInput-fork_Cancun-d2g1v0",
)

# All tests that recursively create a large number of frames (50000)
BIG_MEMORY_TESTS = (
    # GeneralStateTests
    "50000_",
    "/stQuadraticComplexityTest/",
    "/stRandom2/",
    "/stRandom/",
    "/stSpecialTest/",
    "stTimeConsuming/",
    "stBadOpcode/",
    "stStaticCall/",
)


# Modexp test that use exponent_head > 31 bytes
with open(f"{Path().cwd()}/skip-ef-tests.json", "r") as f:
    SKIPPED_TESTS = tuple(json.load(f))


# Define Tests
fetch_tests = partial(
    fetch_state_test_files,
    network=NETWORK,
    ignore_list=IGNORE_TESTS,
    slow_list=SLOW_TESTS,
    big_memory_list=BIG_MEMORY_TESTS,
)


FIXTURES_LOADER = LoadKethFixture(NETWORK, PACKAGE)


@pytest.fixture(scope="module")
def cairo_state_transition(cairo_run, request: pytest.FixtureRequest):  # noqa
    return partial(
        run_blockchain_st_test,
        load=FIXTURES_LOADER,
        cairo_run=cairo_run,
        request=request,
    )


# Run tests from ethereum/tests
@pytest.mark.parametrize(
    "test_case",
    fetch_tests(ETHEREUM_BLOCKCHAIN_TESTS_DIR),
    ids=idfn,
)
def test_general_state_tests(test_case: Dict, cairo_state_transition) -> None:
    cairo_state_transition(test_case)


# Run EEST test fixtures
@pytest.mark.parametrize(
    "test_case",
    fetch_cancun_tests(EEST_BLOCKCHAIN_TESTS_DIR),
    ids=idfn,
)
def test_execution_specs_generated_tests(
    test_case: Dict, cairo_state_transition
) -> None:
    cairo_state_transition(test_case)
