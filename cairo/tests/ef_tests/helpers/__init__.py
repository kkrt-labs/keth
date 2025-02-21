# Update the links and commit has in order to consume
# newer/other tests
TEST_FIXTURES = {
    "execution_spec_tests": {
        "url": "https://github.com/ethereum/execution-spec-tests/releases/download/v0.4.0/fixtures.tar.gz",
        "fixture_path": "cairo/tests/ef_tests/fixtures/execution_spec_tests",
    },
    "evm_tools_testdata": {
        "url": "https://github.com/gurukamath/evm-tools-testdata.git",
        "commit_hash": "792422d",
        "fixture_path": "cairo/tests/ef_tests/fixtures/evm_tools_testdata",
    },
    "ethereum_tests": {
        "url": "https://github.com/ethereum/tests.git",
        "commit_hash": "131b6c879d4b55410312b028a6e4b59ae655ac3d",
        "fixture_path": "cairo/tests/ef_tests/fixtures/ethereum_tests",
    },
}
