// Error types common across all Ethereum forks.
//
// When raising an exception, the exception is a valid pointer. Otherwise, the pointer is `0`. When
// checking for an exception, a simple cast(maybe_exception, felt) != 0 is enough to check if the
// function raised.
//
// Example:
// This is an error:
// ```
// let error = cast(0, EthereumException*);
// ```
//
// This is not an error:
// ```
// from ethereum.cancun.vm.exceptions import StackUnderflowError
// tempvar no_error = new EthereumException(StackUnderflowError);
// ```

// @notice Base type for all exceptions _expected_ to be thrown during normal
// operation.
struct EthereumException {
    value: felt,
}
