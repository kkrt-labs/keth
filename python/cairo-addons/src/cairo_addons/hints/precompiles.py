from starkware.cairo.lang.vm.memory_dict import MemoryDict
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager
from starkware.cairo.lang.vm.relocatable import RelocatableValue
from starkware.cairo.lang.vm.vm_consts import VmConsts

from cairo_addons.hints.decorator import register_hint


@register_hint
def modexp_gas(
    ids: VmConsts,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    from ethereum.cancun.vm.precompiled_contracts.modexp import gas_cost
    from ethereum_types.numeric import U256, Uint

    from cairo_addons.utils.uint256 import uint256_to_int

    base_length = U256(
        uint256_to_int(ids.base_length.value.low, ids.base_length.value.high)
    )
    modulus_length = U256(
        uint256_to_int(ids.modulus_length.value.low, ids.modulus_length.value.high)
    )
    exp_length = U256(
        uint256_to_int(ids.exp_length.value.low, ids.exp_length.value.high)
    )
    exp_head = Uint(uint256_to_int(ids.exp_head.value.low, ids.exp_head.value.high))

    modexp_gas = gas_cost(base_length, modulus_length, exp_length, exp_head)
    memory[ap - 1] = int(modexp_gas)


@register_hint
def modexp_output(
    ids: VmConsts,
    segments: MemorySegmentManager,
    memory: MemoryDict,
    ap: RelocatableValue,
):
    from ethereum_types.numeric import Uint

    base = Uint.from_be_bytes(
        bytes(
            [memory[ids.base.value.data + i] for i in range(ids.base_length.value.low)]
        )
    )
    exp = Uint.from_be_bytes(
        bytes([memory[ids.exp.value.data + i] for i in range(ids.exp_length.value.low)])
    )
    modulus = Uint.from_be_bytes(
        bytes(
            [
                memory[ids.modulus.value.data + i]
                for i in range(ids.modulus_length.value.low)
            ]
        )
    )
    result = pow(base, exp, modulus) if modulus != 0 else 0
    if result == 0:
        result_bytes = b"\x00" * ids.modulus_length.value.low
    else:
        result_bytes = result.to_bytes(ids.modulus_length.value.low, "big")

    data_ptr = segments.add()
    segments.write_arg(data_ptr, result_bytes)
    bytes_ptr = segments.add()
    segments.write_arg(bytes_ptr, [data_ptr, len(result_bytes)])
    memory[ap - 1] = bytes_ptr
