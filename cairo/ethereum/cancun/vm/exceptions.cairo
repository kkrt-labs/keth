from ethereum_types.bytes import Bytes

struct StackUnderflowError {
    value: Bytes,
}

struct StackOverflowError {
    value: Bytes,
}
