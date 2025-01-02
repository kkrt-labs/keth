from ethereum_types.bytes import BytesStruct

struct StackUnderflowError {
    value: BytesStruct*,
}

struct StackOverflowError {
    value: BytesStruct*,
}
