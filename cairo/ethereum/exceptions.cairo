// Error types common across all Ethereum forks.
//
// When raising an exception, the exception is a valid pointer. Otherwise, the pointer is `0`. When
// checking for an exception, a simple cast(maybe_exception, felt) != 0 is enough to check if the
// function raised.
//
// Example:
// This is not an error:
// ```
// let no_error = cast(0, EthereumException*);
// ```
//
// This is an error:
// ```
// from ethereum.cancun.vm.exceptions import StackUnderflowError
// tempvar error = new EthereumException(StackUnderflowError);
// ```

// @notice Base type for all exceptions _expected_ to be thrown during normal
// operation.
struct EthereumException {
    value: felt,
}

// Same purpose as the above struct, only meant to be used in entrypoints.
// required for args_gen and serde in when used in entrypoints. Equivalent to EthereumException*.
struct OptionalEthereumException {
    value: felt*,
}

const ValueError = 'ValueError';
