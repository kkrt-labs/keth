def int_to_uint384(value):
    d0 = value & ((1 << 96) - 1)
    d1 = (value >> 96) & ((1 << 96) - 1)
    d2 = (value >> 192) & ((1 << 96) - 1)
    d3 = (value >> 288) & ((1 << 96) - 1)
    return d0, d1, d2, d3


def uint384_to_int(d0, d1, d2, d3):
    return d0 + d1 * 2**96 + d2 * 2**192 + d3 * 2**288
