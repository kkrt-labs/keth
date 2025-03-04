from functools import partial
from pathlib import Path
from typing import Dict

import pytest

from tests.conftest import cairo_run as cairo_run_ethereum_tests  # noqa
from tests.ef_tests.helpers import TEST_FIXTURES
from tests.ef_tests.helpers.load_state_tests import (
    Load,
    fetch_state_test_files,
    idfn,
    run_blockchain_st_test,
)

pytestmark = [
    pytest.mark.cairo_file(f"{Path().cwd()}/cairo/ethereum/cancun/fork.cairo"),
    pytest.mark.max_steps(200_000_000),
]

fetch_cancun_tests = partial(fetch_state_test_files, network="Cancun")

FIXTURES_LOADER = Load("Cancun", "cancun")

ETHEREUM_TESTS_PATH = TEST_FIXTURES["ethereum_tests"]["fixture_path"]
ETHEREUM_SPEC_TESTS_PATH = TEST_FIXTURES["execution_spec_tests"]["fixture_path"]


# Run state tests
test_dir = f"{ETHEREUM_TESTS_PATH}/BlockchainTests/"

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

fetch_state_tests = partial(
    fetch_cancun_tests,
    test_dir,
    ignore_list=IGNORE_TESTS,
    slow_list=SLOW_TESTS,
    big_memory_list=BIG_MEMORY_TESTS,
)


@pytest.fixture(scope="module")
def cairo_state_transition(
    cairo_run_ethereum_tests, request: pytest.FixtureRequest  # noqa
):
    return partial(
        run_blockchain_st_test,
        load=FIXTURES_LOADER,
        cairo_run=cairo_run_ethereum_tests,
        request=request,
    )


@pytest.mark.parametrize(
    "test_case",
    fetch_state_tests(),
    ids=idfn,
)
def test_general_state_tests(test_case: Dict, cairo_state_transition) -> None:
    cairo_state_transition(test_case)


# Run execution-spec-generated-tests
test_dir = f"{ETHEREUM_SPEC_TESTS_PATH}/fixtures/withdrawals"


@pytest.mark.parametrize(
    "test_case",
    fetch_cancun_tests(test_dir),
    ids=idfn,
)
def test_execution_specs_generated_tests(
    test_case: Dict, cairo_state_transition
) -> None:
    cairo_state_transition(test_case)
