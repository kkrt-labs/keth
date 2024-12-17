// Error types common across all Ethereum forks.
//
// When raising an exception, the exception is a valid pointer. Otherwise, the pointer is `0`. When
// checking for an exceptino, a simple cast(maybe_exception, felt) != 0 is enough to check if the
// function raised.
//
// Example:
// This is an error:
// ```
// tempvar inner_error = new BytesStruct(cast(0, felt*), 0);
// let error = EthereumException(inner_error);
// ```
//
// This is not an error:
// ```
// tempvar no_error = EthereumException(cast(0, BytesStruct*));
// ```

from ethereum_types.bytes import BytesStruct

// @notice Base type for all exceptions _expected_ to be thrown during normal
// operation.
struct EthereumException {
    value: BytesStruct*,
}
