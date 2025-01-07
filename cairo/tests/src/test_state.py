import pytest

from ethereum.cancun.fork_types import EMPTY_ACCOUNT
from ethereum.crypto.hash import keccak256
from src.utils.uint256 import int_to_uint256
from tests.utils.constants import OTHER, OWNER
from tests.utils.helpers import get_internal_storage_key
from tests.utils.models import State

pytestmark = pytest.mark.python_vm


class TestState:
    class TestInit:
        def test_should_return_state_with_default_dicts(self, cairo_run):
            cairo_run("test__init__should_return_state_with_default_dicts")

    class TestIsAccountWarm:
        def test_should_return_true_when_account_in_state(self, cairo_run):
            cairo_run("test__is_account_warm__account_in_state")

    class TestAddTransfer:
        def test_should_return_false_when_overflowing_recipient_balance(
            self, cairo_run
        ):
            cairo_run(
                "test__add_transfer_should_return_false_when_overflowing_recipient_balance"
            )

    class TestGetAccount:
        def test_should_return_account_when_account_in_state(self, cairo_run):
            initial_state = {
                OWNER: {
                    "code": [],
                    "storage": {0x1: 0x2},
                    "balance": int(1e18),
                    "nonce": 0,
                }
            }
            account = cairo_run(
                "test__get_account",
                evm_address=int(OWNER, 16),
                state=State.model_validate(initial_state),
            )
            expected = {
                "code": bytes(initial_state[OWNER]["code"]),
                "code_hash": int.from_bytes(
                    keccak256(bytes(initial_state[OWNER]["code"])), "big"
                ),
                "balance": initial_state[OWNER]["balance"],
                "nonce": initial_state[OWNER]["nonce"],
                "storage": {
                    get_internal_storage_key(k): {
                        "low": int_to_uint256(v)[0],
                        "high": int_to_uint256(v)[1],
                    }
                    for k, v in initial_state[OWNER]["storage"].items()
                },
                "transient_storage": {},
                "valid_jumpdests": {},
                "selfdestruct": 0,
                "created": 0,
            }
            assert account == expected

        def test_should_return_default_account_when_account_not_in_state(
            self, cairo_run
        ):
            account = cairo_run(
                "test__get_account",
                evm_address=int(OTHER, 16),
                state=State.model_validate({}),
            )
            expected = {
                "code": EMPTY_ACCOUNT.code,
                "code_hash": int.from_bytes(keccak256(EMPTY_ACCOUNT.code), "big"),
                "balance": EMPTY_ACCOUNT.balance,
                "nonce": EMPTY_ACCOUNT.nonce,
                "storage": {},
                "transient_storage": {},
                "valid_jumpdests": {},
                "selfdestruct": 0,
                "created": 0,
            }

            assert account == expected
