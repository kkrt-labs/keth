from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, PoseidonBuiltin, ModBuiltin
from starkware.cairo.common.math_cmp import is_le_felt
from ethereum.prague.vm.evm_impl import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.prague.vm.exceptions import OutOfGasError
from ethereum.utils.numeric import ceil32
from ethereum.prague.vm.gas import GasConstants, charge_gas
from ethereum_types.numeric import Uint

from cairo_core.hash.sha256 import sha256_bytes

// @notice Writes the sha256 hash to output.
func sha256{
    range_check_ptr,
    bitwise_ptr: BitwiseBuiltin*,
    keccak_ptr: felt*,
    poseidon_ptr: PoseidonBuiltin*,
    range_check96_ptr: felt*,
    add_mod_ptr: ModBuiltin*,
    mul_mod_ptr: ModBuiltin*,
    evm: Evm,
}() -> EthereumException* {
    alloc_locals;
    let data = evm.value.message.value.data;

    // Gas
    let ceiled_words = ceil32(Uint(data.value.len));
    let word_count = ceiled_words.value / 32;  // simple div as we're dividing a number divisible by 32
    let size_oog = is_le_felt(2 ** 31, word_count);
    if (size_oog != 0) {
        tempvar err = new EthereumException(OutOfGasError);
        return err;
    }
    let gas_cost = Uint(word_count * GasConstants.GAS_SHA256_WORD + GasConstants.GAS_SHA256);
    let err = charge_gas(gas_cost);
    if (cast(err, felt) != 0) {
        return err;
    }

    let hash_bytes = sha256_bytes(data);

    EvmImpl.set_output(hash_bytes);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}
