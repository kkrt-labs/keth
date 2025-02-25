from ethereum.cancun.vm.exceptions import KZGProofError
from ethereum.cancun.vm.gas import GAS_POINT_EVALUATION
from ethereum.cancun.vm.precompiled_contracts.point_evaluation import point_evaluation
from hypothesis import given
from hypothesis import strategies as st

from cairo_addons.testing.errors import strict_raises
from tests.utils.evm_builder import EvmBuilder
from tests.utils.message_builder import MessageBuilder


def invalid_data():
    invalid_length_data = st.binary(min_size=0, max_size=512)
    mismatched_versioned_hash_data = st.binary(min_size=192, max_size=192)
    return (
        EvmBuilder()
        .with_gas_left(st.just(GAS_POINT_EVALUATION))
        .with_message(
            MessageBuilder()
            .with_data(st.one_of(invalid_length_data, mismatched_versioned_hash_data))
            .build()
        )
        .build()
    )


class TestPointEvaluation:
    @given(evm=invalid_data())
    def test_invalid_length(self, cairo_run, evm):
        with strict_raises(KZGProofError):
            cairo_run("point_evaluation", evm=evm)

        with strict_raises(KZGProofError):
            point_evaluation(evm)
