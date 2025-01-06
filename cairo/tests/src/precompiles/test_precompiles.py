import pytest

from tests.utils.constants import LAST_ETHEREUM_PRECOMPILE_ADDRESS
from tests.utils.errors import cairo_error

pytestmark = pytest.mark.python_vm


class TestPrecompiles:
    class TestRun:
        def test__precompile_zero_invalid_precompile(self, cairo_run):
            with cairo_error("Precompile called but does not exist"):
                cairo_run("test__precompiles_run", address=0x0, input=[])

        class TestEthereumPrecompiles:
            @pytest.mark.parametrize(
                "address, error_message",
                [
                    (0x6, "Kakarot: NotImplementedPrecompile 6"),
                    (0x7, "Kakarot: NotImplementedPrecompile 7"),
                    (0x8, "Kakarot: NotImplementedPrecompile 8"),
                    (0x0A, "Kakarot: NotImplementedPrecompile 10"),
                ],
            )
            def test__precompiles_run_should_fail(
                self, cairo_run, address, error_message
            ):
                return_data, reverted, _ = cairo_run(
                    "test__precompiles_run", address=address, input=[]
                )
                assert bytes(return_data).decode() == error_message
                assert reverted

    class TestIsPrecompile:
        @pytest.mark.parametrize(
            "address", range(0, LAST_ETHEREUM_PRECOMPILE_ADDRESS + 2)
        )
        def test__is_precompile_ethereum_precompiles(self, cairo_run, address):
            result = cairo_run("test__is_precompile", address=address)

            assert result == (address in range(1, LAST_ETHEREUM_PRECOMPILE_ADDRESS + 1))
