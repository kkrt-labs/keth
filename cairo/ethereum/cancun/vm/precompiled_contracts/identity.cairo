from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_le_felt
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import OutOfGasError
from ethereum.utils.numeric import ceil32
from ethereum.cancun.vm.gas import GasConstants, charge_gas
from ethereum_types.numeric import Uint

// @notice Writes the message data to the output
func identity{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*, evm: Evm}(
    ) -> EthereumException* {
    let data = evm.value.message.value.data;

    // Gas
    let ceiled_words = ceil32(Uint(data.value.len));
    let word_count = ceiled_words.value / 32;  // simple div as we're dividing a number divisible by 32
    let size_oog = is_le_felt(2 ** 31, word_count);
    if (size_oog != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }
    let gas_cost = Uint(word_count * GasConstants.GAS_IDENTITY_WORD + GasConstants.GAS_IDENTITY);
    let err = charge_gas(gas_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    // Output and Data fields are pointers to the same segment. However these segments are never appended,
    // thus we can do this safely and avoid a memcpy.
    EvmImpl.set_output(data);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}
