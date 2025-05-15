from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


def write_error(
    memory: MemoryDict,
    ap: RelocatableValue,
    segments: MemorySegmentManager,
    error: Exception,
):
    error_int = int.from_bytes(error.__class__.__name__.encode("ascii"), "big")
    data_ptr = segments.add()
    segments.load_data(data_ptr, [error_int])
    memory[ap - 2] = data_ptr
    return


def write_output(
    memory: MemoryDict,
    ap: RelocatableValue,
    segments: MemorySegmentManager,
    output: bytes,
):
    data_ptr = segments.add()
    segments.load_data(data_ptr, output)
    bytes_ptr = segments.add()
    segments.load_data(bytes_ptr, [data_ptr, len(output)])
    memory[ap - 1] = bytes_ptr


@register_hint
def bit_length_hint(ids: VmConsts, memory: MemoryDict, ap: RelocatableValue):
    memory[ap - 1] = ids.value.bit_length()


@register_hint
def bytes_length_hint(ids: VmConsts, memory: MemoryDict, ap: RelocatableValue):
    memory[ap - 1] = (ids.value.bit_length() + 7) // 8


@register_hint
def bls12_g1_add_hint(
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):

    from ethereum.prague.vm.memory import buffer_read
    from ethereum.prague.vm.precompiled_contracts.bls12_381.bls12_381_g1 import (
        G1_to_bytes,
        bytes_to_G1,
    )
    from ethereum_types.numeric import U256
    from py_ecc.bls12_381.bls12_381_curve import add

    from cairo_addons.hints.precompiles import write_error, write_output

    def inner():
        data = bytes(
            [memory[ids.data.value.data + i] for i in range(ids.data.value.len)]
        )
        try:
            p1 = bytes_to_G1(buffer_read(data, U256(0), U256(128)))
            p2 = bytes_to_G1(buffer_read(data, U256(128), U256(128)))

            result = G1_to_bytes(add(p1, p2))

            memory[ap - 2] = 0
            write_output(memory, ap, segments, result)
        except Exception as e:
            write_error(memory, ap, segments, e)

    inner()


@register_hint
def bls12_g1_msm_hint(
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    from ethereum.prague.vm.gas import GAS_BLS_G1_MUL
    from ethereum.prague.vm.precompiled_contracts.bls12_381.bls12_381_g1 import (
        G1_K_DISCOUNT,
        G1_MAX_DISCOUNT,
        MULTIPLIER,
        G1_to_bytes,
        decode_G1_scalar_pair,
    )
    from ethereum_types.numeric import Uint
    from py_ecc.bls12_381.bls12_381_curve import add, multiply

    from cairo_addons.hints.precompiles import write_error, write_output

    def inner():
        data = bytes(
            [memory[ids.data.value.data + i] for i in range(ids.data.value.len)]
        )
        try:
            # Each pair consists of a G1 point (128 bytes) and a scalar (32 bytes)
            LENGTH_PER_PAIR = 160
            if len(data) == 0 or len(data) % LENGTH_PER_PAIR != 0:
                raise ValueError("Invalid Input Length")

            k = len(data) // LENGTH_PER_PAIR
            if k <= 128:
                discount = Uint(G1_K_DISCOUNT[k - 1])
            else:
                discount = Uint(G1_MAX_DISCOUNT)
            # TODO
            # gas_cost = Uint(k) * GAS_BLS_G1_MUL * discount // MULTIPLIER
            # charge_gas(evm, gas_cost)

            # OPERATION
            for i in range(k):
                start_index = i * LENGTH_PER_PAIR
                end_index = start_index + LENGTH_PER_PAIR

                p, m = decode_G1_scalar_pair(data[start_index:end_index])
                product = multiply(p, m)

                if i == 0:
                    result = product
                else:
                    result = add(result, product)

            # Convert final result to bytes
            output = G1_to_bytes(result)

            memory[ap - 2] = 0
            write_output(memory, ap, segments, output)
        except Exception as e:
            write_error(memory, ap, segments, e)

    inner()
