from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin, KeccakBuiltin
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.memset import memset
from ethereum.cancun.vm import Evm, EvmImpl
from ethereum.exceptions import EthereumException
from ethereum.cancun.vm.exceptions import OutOfGasError
from ethereum.utils.numeric import ceil32
from ethereum.utils.bytes import Bytes4, Bytes_to_be_ListBytes4, ListBytes4_be_to_bytes
from ethereum.cancun.vm.gas import GasConstants, charge_gas
from ethereum_types.numeric import Uint
from ethereum_types.bytes import Bytes, BytesStruct, ListBytes4, ListBytes4Struct

from src.utils.utils import Helpers
from cairo_core.hash.sha256 import sha256_be_output
from cairo_core.maths import unsigned_div_rem

// @notice Writes the sha256 hash to output.
func sha256{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, keccak_ptr: KeccakBuiltin*, evm: Evm}(
    ) -> EthereumException* {
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

    let list_bytes4_be = Bytes_to_be_ListBytes4(data);

    // The numbero of bytes to hash is taken from the original input
    let hash = sha256_be_output(list_bytes4_be.value.data, data.value.len);
    tempvar hash_bytes4 = ListBytes4(new ListBytes4Struct(cast(hash, Bytes4*), 8));

    // Split words and return bytes hash code.
    let hash_bytes = ListBytes4_be_to_bytes(hash_bytes4);

    EvmImpl.set_output(hash_bytes);
    tempvar ok = cast(0, EthereumException*);
    return ok;
}
