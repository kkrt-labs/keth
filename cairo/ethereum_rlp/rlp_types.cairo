from ethereum_types.bytes import Bytes, String
from ethereum_types.numeric import Uint, Bool

struct SequenceSimple {
    value: SequenceSimpleStruct*,
}

struct SequenceSimpleStruct {
    data: Simple*,
    len: felt,
}

struct Simple {
    value: SimpleEnum*,
}

struct SimpleEnum {
    sequence: SequenceSimple,
    bytes: Bytes,
}

struct SequenceExtended {
    value: SequenceExtendedStruct*,
}

struct SequenceExtendedStruct {
    data: Extended*,
    len: felt,
}

struct Extended {
    value: ExtendedEnum*,
}

struct ExtendedEnum {
    sequence: SequenceExtended,
    bytearray: Bytes,
    bytes: Bytes,
    uint: Uint*,
    fixed_uint: Uint*,
    str: String,
    bool: Bool*,
}
