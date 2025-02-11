from ethereum.cancun.vm.precompiled_contracts.mapping import (
    ECRECOVER_ADDRESS,
    PRE_COMPILED_CONTRACTS,
)
from hypothesis import example, given
from hypothesis import strategies as st

from cairo_addons.testing.errors import cairo_error
from cairo_addons.testing.hints import patch_hint


class TestPrecompileMapping:
    @given(address=st.sampled_from(list(PRE_COMPILED_CONTRACTS.keys())))
    def test_precompile_table_lookup_valid_addresses(self, cairo_run, address):
        address_int = int.from_bytes(address, "little")
        table_address, _fn_ptr = cairo_run("precompile_table_lookup", address_int)
        assert table_address == address_int

    @given(
        address_int=st.integers(min_value=0, max_value=2**160 - 1).filter(
            lambda x: x.to_bytes(20, "big") not in PRE_COMPILED_CONTRACTS.keys()
        )
    )
    @example(address_int=0x0B00000000000000000000000000000000000000)
    def test_precompile_table_lookup_invalid_addresses(self, cairo_run, address_int):
        table_address, _fn_ptr = cairo_run("precompile_table_lookup", address_int)
        assert table_address == 0

    @given(address=st.sampled_from(list(PRE_COMPILED_CONTRACTS.keys())))
    def test_precompile_table_lookup_hint_index_out_of_bounds(
        self, cairo_programs, cairo_run_py, address
    ):
        address_int = int.from_bytes(address, "little")
        with (
            patch_hint(
                cairo_programs,
                "precompile_index_from_address",
                f"ids.index = {len(PRE_COMPILED_CONTRACTS)*3 + 1}",
            ),
            cairo_error(message="precompile_table_lookup: index out of bounds"),
        ):
            cairo_run_py("precompile_table_lookup", address_int)

    @given(address=st.sampled_from(list(PRE_COMPILED_CONTRACTS.keys())))
    def test_precompile_table_lookup_hint_index_different_address(
        self, cairo_programs, cairo_run_py, address
    ):
        address_int = int.from_bytes(address, "little")
        with (
            patch_hint(
                cairo_programs,
                "precompile_index_from_address",
                f"ids.index = {0 if address != ECRECOVER_ADDRESS else 1}",
            ),
            cairo_error(message="precompile_table_lookup: address mismatch"),
        ):
            cairo_run_py("precompile_table_lookup", address_int)
