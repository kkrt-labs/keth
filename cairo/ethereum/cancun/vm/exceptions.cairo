from ethereum_types.bytes import BytesStruct

struct StackUnderflowError {
    value: BytesStruct*,
}

struct StackOverflowError {
    value: BytesStruct*,
}

struct OutOfGasError {
    value: BytesStruct*,
}

struct InvalidOpcodeError {
    value: BytesStruct*,
}

struct InvalidJumpDestError {
    value: BytesStruct*,
}

struct StackDepthLimitError {
    value: BytesStruct*,
}

struct WriteInStaticContextError {
    value: BytesStruct*,
}

struct OutOfBoundsReadError {
    value: BytesStruct*,
}

struct InvalidParameterError {
    value: BytesStruct*,
}

struct InvalidContractPrefixError {
    value: BytesStruct*,
}

struct AddressCollisionError {
    value: BytesStruct*,
}

struct KZGProofError {
    value: BytesStruct*,
}
