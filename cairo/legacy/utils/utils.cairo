from starkware.cairo.common.math_cmp import is_nn
from starkware.cairo.common.math import assert_nn_le
from starkware.cairo.common.bool import FALSE, TRUE
from starkware.cairo.common.uint256 import Uint256

// @title Helper Functions
// @notice This file contains a selection of helper function that simplify tasks such as type conversion and bit manipulation
namespace Helpers {
    // @notice This function is used to convert a sequence of 32 bytes to Uint256.
    // @param val: pointer to the first byte of the 32.
    // @return res: Uint256 representation of the given input in bytes32.
    func bytes32_to_uint256(val: felt*) -> Uint256 {
        let low = [val + 16] * 256 ** 15;
        let low = low + [val + 17] * 256 ** 14;
        let low = low + [val + 18] * 256 ** 13;
        let low = low + [val + 19] * 256 ** 12;
        let low = low + [val + 20] * 256 ** 11;
        let low = low + [val + 21] * 256 ** 10;
        let low = low + [val + 22] * 256 ** 9;
        let low = low + [val + 23] * 256 ** 8;
        let low = low + [val + 24] * 256 ** 7;
        let low = low + [val + 25] * 256 ** 6;
        let low = low + [val + 26] * 256 ** 5;
        let low = low + [val + 27] * 256 ** 4;
        let low = low + [val + 28] * 256 ** 3;
        let low = low + [val + 29] * 256 ** 2;
        let low = low + [val + 30] * 256 ** 1;
        let low = low + [val + 31];
        let high = [val] * 256 ** 1 * 256 ** 14;
        let high = high + [val + 1] * 256 ** 14;
        let high = high + [val + 2] * 256 ** 13;
        let high = high + [val + 3] * 256 ** 12;
        let high = high + [val + 4] * 256 ** 11;
        let high = high + [val + 5] * 256 ** 10;
        let high = high + [val + 6] * 256 ** 9;
        let high = high + [val + 7] * 256 ** 8;
        let high = high + [val + 8] * 256 ** 7;
        let high = high + [val + 9] * 256 ** 6;
        let high = high + [val + 10] * 256 ** 5;
        let high = high + [val + 11] * 256 ** 4;
        let high = high + [val + 12] * 256 ** 3;
        let high = high + [val + 13] * 256 ** 2;
        let high = high + [val + 14] * 256;
        let high = high + [val + 15];
        let res = Uint256(low=low, high=high);
        return res;
    }
    // @notice This function is used to convert bytes array in big-endian to Uint256.
    // @dev The function is limited to 32 bytes or less.
    // @param bytes_len: bytes array length.
    // @param bytes: pointer to the first byte of the bytes array.
    // @return res: Uint256 representation of the given input in bytes.
    func bytes_to_uint256{range_check_ptr}(bytes_len: felt, bytes: felt*) -> Uint256 {
        alloc_locals;

        if (bytes_len == 0) {
            let res = Uint256(0, 0);
            return res;
        }

        let is_bytes_len_16_bytes_or_less = is_nn(16 - bytes_len);

        // 1 - 16 bytes
        if (is_bytes_len_16_bytes_or_less != FALSE) {
            let low = bytes_to_felt(bytes_len, bytes);
            let res = Uint256(low=low, high=0);

            return res;
        }

        // 17 - 32 bytes
        let low = bytes_to_felt(16, bytes + bytes_len - 16);
        let high = bytes_to_felt(bytes_len - 16, bytes);
        let res = Uint256(low=low, high=high);

        return res;
    }

    // @notice Loads a sequence of bytes into a single felt in big-endian.
    // @param len: number of bytes.
    // @param ptr: pointer to bytes array.
    // @return: packed felt.
    func bytes_to_felt(len: felt, ptr: felt*) -> felt {
        if (len == 0) {
            return 0;
        }
        tempvar current = 0;

        // len, ptr, ?, ?, current
        // ?, ? are intermediate steps created by the compiler to unfold the
        // complex expression.
        loop:
        let len = [ap - 5];
        let ptr = cast([ap - 4], felt*);
        let current = [ap - 1];

        tempvar len = len - 1;
        tempvar ptr = ptr + 1;
        tempvar current = current * 256 + [ptr - 1];

        static_assert len == [ap - 5];
        static_assert ptr == [ap - 4];
        static_assert current == [ap - 1];
        jmp loop if len != 0;

        return current;
    }

    // @notice Load sequences of 8 bytes little endian into an array of felts
    // @param len: final length of the output.
    // @param input: pointer to bytes array input.
    // @param output: pointer to bytes array output.
    func load_64_bits_array(len: felt, input: felt*, output: felt*) {
        if (len == 0) {
            return ();
        }
        let loaded = bytes_to_64_bits_little_felt(input);
        assert [output] = loaded;
        return load_64_bits_array(len - 1, input + 8, output + 1);
    }

    // @notice This function is used to convert a sequence of 8 bytes to a felt.
    // @param val: pointer to the first byte.
    // @return: felt representation of the input.
    func bytes_to_64_bits_little_felt(bytes: felt*) -> felt {
        let res = [bytes + 7] * 256 ** 7;
        let res = res + [bytes + 6] * 256 ** 6;
        let res = res + [bytes + 5] * 256 ** 5;
        let res = res + [bytes + 4] * 256 ** 4;
        let res = res + [bytes + 3] * 256 ** 3;
        let res = res + [bytes + 2] * 256 ** 2;
        let res = res + [bytes + 1] * 256;
        let res = res + [bytes];
        return res;
    }

    // @notice Splits a felt into `len` bytes, little-endian, and outputs to `dst`.
    func split_word_little{range_check_ptr}(value: felt, len: felt, dst: felt*) {
        if (len == 0) {
            with_attr error_message("value not empty") {
                assert value = 0;
            }
            return ();
        }
        with_attr error_message("len must be < 32") {
            assert is_nn(31 - len) = TRUE;
        }
        let output = &dst[0];
        let base = 256;
        let bound = 256;
        %{
            memory[ids.output] = res = (int(ids.value) % PRIME) % ids.base
            assert res < ids.bound, f'split_int(): Limb {res} is out of range.'
        %}
        tempvar low_part = [output];
        assert_nn_le(low_part, 255);
        return split_word_little((value - low_part) / 256, len - 1, dst + 1);
    }
}
