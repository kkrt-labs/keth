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

    from cairo_addons.hints.precompiles import write_output

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

    write_output(memory, ap, segments, result_bytes)


@register_hint
def alt_bn128_pairing_check_hint(
    ids: VmConsts,
    memory: MemoryDict,
    ap: RelocatableValue,
    segments: MemorySegmentManager,
):

    from ethereum.cancun.vm.exceptions import OutOfGasError
    from ethereum.crypto.alt_bn128 import (
        ALT_BN128_CURVE_ORDER,
        ALT_BN128_PRIME,
        BNF,
        BNF2,
        BNF12,
        BNP,
        BNP2,
        pairing,
    )
    from ethereum_types.numeric import U256

    from cairo_addons.hints.precompiles import write_error, write_output

    def inner():
        data = [memory[ids.data.value.data + i] for i in range(ids.data.value.len)]

        # Adapted execution specs
        # <https://github.com/ethereum/execution-specs/blob/78fb726158c69d8fa164e28f195fabf6ab59b915/src/ethereum/paris/vm/precompiled_contracts/alt_bn128.py#L33>
        result = BNF12.from_int(1)
        for i in range(len(data) // 192):
            values = []
            for j in range(6):
                value = int(
                    U256.from_be_bytes(data[i * 192 + 32 * j : i * 192 + 32 * (j + 1)])
                )
                if value >= ALT_BN128_PRIME:
                    write_error(memory, ap, segments, OutOfGasError)
                    return
                values.append(value)

            try:
                p = BNP(BNF(values[0]), BNF(values[1]))
                q = BNP2(BNF2((values[3], values[2])), BNF2((values[5], values[4])))
            except ValueError:
                write_error(memory, ap, segments, OutOfGasError)
                return
            if p.mul_by(ALT_BN128_CURVE_ORDER) != BNP.point_at_infinity():
                write_error(memory, ap, segments, OutOfGasError)
                return
            if q.mul_by(ALT_BN128_CURVE_ORDER) != BNP2.point_at_infinity():
                write_error(memory, ap, segments, OutOfGasError)
                return
            if p != BNP.point_at_infinity() and q != BNP2.point_at_infinity():
                result = result * pairing(q, p)

        if result == BNF12.from_int(1):
            output = U256(1).to_be_bytes32()
        else:
            output = U256(0).to_be_bytes32()

        # No error
        memory[ap - 2] = 0
        write_output(memory, ap, segments, output)

    inner()


@register_hint
def alt_bn128_add_hint(
    ids: VmConsts,
    memory: MemoryDict,
    ap: RelocatableValue,
    segments: MemorySegmentManager,
):
    from ethereum.cancun.vm.exceptions import OutOfGasError
    from ethereum.crypto.alt_bn128 import ALT_BN128_PRIME, BNF, BNP

    from cairo_addons.hints.precompiles import write_error, write_output
    from cairo_addons.utils.uint256 import uint256_to_int

    def inner():
        x0_value = uint256_to_int(ids.x0_value.value.low, ids.x0_value.value.high)
        y0_value = uint256_to_int(ids.y0_value.value.low, ids.y0_value.value.high)
        x1_value = uint256_to_int(ids.x1_value.value.low, ids.x1_value.value.high)
        y1_value = uint256_to_int(ids.y1_value.value.low, ids.y1_value.value.high)

        # Adapted execution specs
        # <https://github.com/ethereum/execution-specs/blob/78fb726158c69d8fa164e28f195fabf6ab59b915/src/ethereum/paris/vm/precompiled_contracts/alt_bn128.py#L33>
        for i in (x0_value, y0_value, x1_value, y1_value):
            if i >= ALT_BN128_PRIME:
                write_error(memory, ap, segments, OutOfGasError)
                return

        try:
            p0 = BNP(BNF(x0_value), BNF(y0_value))
            p1 = BNP(BNF(x1_value), BNF(y1_value))
        except ValueError:
            write_error(memory, ap, segments, OutOfGasError)
            return

        p = p0 + p1

        output = p.x.to_be_bytes32() + p.y.to_be_bytes32()

        # No error
        memory[ap - 2] = 0
        write_output(memory, ap, segments, output)

    inner()


@register_hint
def alt_bn128_mul_hint(
    ids: VmConsts,
    memory: MemoryDict,
    ap: RelocatableValue,
    segments: MemorySegmentManager,
):
    from ethereum.cancun.vm.exceptions import OutOfGasError
    from ethereum.crypto.alt_bn128 import ALT_BN128_PRIME, BNF, BNP

    from cairo_addons.hints.precompiles import write_error, write_output
    from cairo_addons.utils.uint256 import uint256_to_int

    def inner():
        x0_value = uint256_to_int(ids.x0_value.value.low, ids.x0_value.value.high)
        y0_value = uint256_to_int(ids.y0_value.value.low, ids.y0_value.value.high)
        n_value = uint256_to_int(ids.n_value.value.low, ids.n_value.value.high)

        # Adapted execution specs
        # <https://github.com/ethereum/execution-specs/blob/78fb726158c69d8fa164e28f195fabf6ab59b915/src/ethereum/paris/vm/precompiled_contracts/alt_bn128.py#L33>
        for i in (x0_value, y0_value):
            if i >= ALT_BN128_PRIME:
                write_error(memory, ap, segments, OutOfGasError)
                return

        try:
            p0 = BNP(BNF(x0_value), BNF(y0_value))
        except ValueError:
            write_error(memory, ap, segments, OutOfGasError)
            return

        p = p0.mul_by(n_value)

        output = p.x.to_be_bytes32() + p.y.to_be_bytes32()

        # No error
        memory[ap - 2] = 0
        write_output(memory, ap, segments, output)

    inner()


def write_error(
    memory: MemoryDict,
    ap: RelocatableValue,
    segments: MemorySegmentManager,
    error: Exception,
):
    error_int = int.from_bytes(error.__name__.encode("ascii"), "big")
    data_ptr = segments.add()
    segments.write_arg(data_ptr, [error_int])
    memory[ap - 2] = data_ptr
    return


def write_output(
    memory: MemoryDict,
    ap: RelocatableValue,
    segments: MemorySegmentManager,
    output: bytes,
):
    data_ptr = segments.add()
    segments.write_arg(data_ptr, output)
    bytes_ptr = segments.add()
    segments.write_arg(bytes_ptr, [data_ptr, len(output)])
    memory[ap - 1] = bytes_ptr


@register_hint
def point_evaluation_hint(
    ids: VmConsts,
    memory: MemoryDict,
    ap: RelocatableValue,
    segments: MemorySegmentManager,
):
    from ethereum.cancun.vm.exceptions import KZGProofError
    from ethereum.crypto.kzg import (
        KZGCommitment,
        kzg_commitment_to_versioned_hash,
        verify_kzg_proof,
    )
    from ethereum_types.bytes import Bytes, Bytes32, Bytes48
    from ethereum_types.numeric import U256

    from cairo_addons.hints.precompiles import write_error, write_output

    def inner():
        data = [memory[ids.data.value.data + i] for i in range(ids.data.value.len)]

        versioned_hash = Bytes32(Bytes(bytes(data[:32])))
        z = Bytes32(Bytes(bytes(data[32:64])))
        y = Bytes32(Bytes(bytes(data[64:96])))
        commitment = KZGCommitment(Bytes48(Bytes(bytes(data[96:144]))))
        proof = Bytes48(Bytes(bytes(data[144:192])))

        try:
            if kzg_commitment_to_versioned_hash(commitment) != versioned_hash:
                write_error(memory, ap, segments, KZGProofError)
                return

            if not verify_kzg_proof(commitment, z, y, proof):
                write_error(memory, ap, segments, KZGProofError)
                return

            FIELD_ELEMENTS_PER_BLOB = 4096
            BLS_MODULUS = 52435875175126190479447740508185965837690552500527637822603658699938581184513

            output_bytes = (
                U256(FIELD_ELEMENTS_PER_BLOB).to_be_bytes32()
                + U256(BLS_MODULUS).to_be_bytes32()
            )

            memory[ap - 2] = 0
            write_output(memory, ap, segments, output_bytes)

        except Exception:
            write_error(memory, ap, segments, KZGProofError)
            return

    inner()


@register_hint
def bit_length_hint(ids: VmConsts, memory: MemoryDict, ap: RelocatableValue):
    memory[ap - 1] = ids.value.value.bit_length()
