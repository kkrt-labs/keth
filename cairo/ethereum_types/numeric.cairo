from starkware.cairo.common.uint256 import Uint256

// Int types
struct bool {
    value: felt,
}
using Bool = bool;
struct U64 {
    value: felt,
}
struct U128 {
    value: felt,
}
struct Uint {
    value: felt,
}
struct U256 {
    value: Uint256*,
}
