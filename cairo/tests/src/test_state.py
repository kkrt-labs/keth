class TestState:
    class TestInit:
        def test_should_return_state_with_default_dicts(self, cairo_run):
            cairo_run("test__init__should_return_state_with_default_dicts")

    class TestIsAccountWarm:
        def test_should_return_true_when_account_in_state(self, cairo_run):
            cairo_run("test__is_account_warm__account_in_state")

    class TestCopyAccounts:
        def test_should_handle_null_pointers(self, cairo_run):
            cairo_run("test___copy_accounts__should_handle_null_pointers")

    class TestAddTransfer:
        def test_should_return_false_when_overflowing_recipient_balance(
            self, cairo_run
        ):
            cairo_run(
                "test__add_transfer_should_return_false_when_overflowing_recipient_balance"
            )
