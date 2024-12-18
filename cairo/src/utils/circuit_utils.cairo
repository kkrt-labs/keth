from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, UInt384, ModBuiltin
from starkware.cairo.common.poseidon_state import PoseidonBuiltinState
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.registers import get_fp_and_pc, get_label_location
from starkware.cairo.common.math import assert_le_felt

const N_LIMBS = 4;
const STARK_MIN_ONE_D2 = 0x800000000000011;

func hash_full_transcript_and_get_Z_3_LIMBS{poseidon_ptr: PoseidonBuiltin*}(
    limbs_ptr: felt*, n: felt
) -> (_s0: felt, _s1: felt, _s2: felt) {
    alloc_locals;
    local BASE = 2 ** 96;
    // %{
    //     from garaga.hints.io import pack_bigint_ptr
    //     to_hash=pack_bigint_ptr(memory, ids.limbs_ptr, ids.N_LIMBS, ids.BASE, ids.n)
    //     for e in to_hash:
    //         print(f"Will Hash {hex(e)}")
    // %}

    let elements_end = &limbs_ptr[n * N_LIMBS];

    tempvar elements = limbs_ptr;
    tempvar pos_ptr = cast(poseidon_ptr, felt*);

    loop:
    if (nondet %{ ids.elements_end - ids.elements >= 6*ids.N_LIMBS %} != 0) {
        // %{
        //     from garaga.hints.io import pack_bigint_ptr
        //     to_hash=pack_bigint_ptr(memory, ids.elements, ids.N_LIMBS, ids.BASE, 6)
        //     for e in to_hash:
        //         print(f"\t Will Hash {hex(e)}")
        // %}

        assert [pos_ptr + 0] = [pos_ptr - 3] + elements[0] + (BASE) * elements[1];
        assert [pos_ptr + 1] = [pos_ptr - 2] + elements[2];
        assert [pos_ptr + 2] = [pos_ptr - 1];

        assert [pos_ptr + 6] = [pos_ptr + 3] + elements[4] + (BASE) * elements[5];
        assert [pos_ptr + 7] = [pos_ptr + 4] + elements[6];
        assert [pos_ptr + 8] = [pos_ptr + 5];

        assert [pos_ptr + 12] = [pos_ptr + 9] + elements[8] + (BASE) * elements[9];
        assert [pos_ptr + 13] = [pos_ptr + 10] + elements[10];
        assert [pos_ptr + 14] = [pos_ptr + 11];

        assert [pos_ptr + 18] = [pos_ptr + 15] + elements[12] + (BASE) * elements[13];
        assert [pos_ptr + 19] = [pos_ptr + 16] + elements[14];
        assert [pos_ptr + 20] = [pos_ptr + 17];

        assert [pos_ptr + 24] = [pos_ptr + 21] + elements[16] + (BASE) * elements[17];
        assert [pos_ptr + 25] = [pos_ptr + 22] + elements[18];
        assert [pos_ptr + 26] = [pos_ptr + 23];

        assert [pos_ptr + 30] = [pos_ptr + 27] + elements[20] + (BASE) * elements[21];
        assert [pos_ptr + 31] = [pos_ptr + 28] + elements[22];
        assert [pos_ptr + 32] = [pos_ptr + 29];

        let pos_ptr = pos_ptr + 6 * PoseidonBuiltin.SIZE;
        tempvar elements = &elements[6 * N_LIMBS];
        tempvar pos_ptr = pos_ptr;
        jmp loop;
    }

    if (nondet %{ ids.elements_end - ids.elements >= ids.N_LIMBS %} != 0) {
        // %{
        //     from garaga.hints.io import pack_bigint_ptr
        //     to_hash=pack_bigint_ptr(memory, ids.elements, ids.N_LIMBS, ids.BASE, 1)
        //     for e in to_hash:
        //         print(f"\t\t Will Hash {e}")
        // %}
        assert [pos_ptr + 0] = [pos_ptr - 3] + elements[0] + (BASE) * elements[1];
        assert [pos_ptr + 1] = [pos_ptr - 2] + elements[2];
        assert [pos_ptr + 2] = [pos_ptr - 1];

        let pos_ptr = pos_ptr + PoseidonBuiltin.SIZE;

        tempvar elements = &elements[N_LIMBS];
        tempvar pos_ptr = pos_ptr;
        jmp loop;
    }

    assert cast(elements_end, felt) = cast(elements, felt);

    tempvar poseidon_ptr = poseidon_ptr + n * PoseidonBuiltin.SIZE;
    let res_ptr = poseidon_ptr - PoseidonBuiltin.SIZE;
    tempvar s0 = [res_ptr].output.s0;
    tempvar s1 = [res_ptr].output.s1;
    tempvar s2 = [res_ptr].output.s2;
    return (_s0=s0, _s1=s1, _s2=s2);
}

// Returns the sign of value: -1 if value < 0, 1 if value > 0.
// value is considered positive if it is in [0, STARK//2[
// value is considered negative if it is in ]STARK//2, STARK[
// If value == 0, returned value can be either 0 or 1 (undetermined).
func sign{range_check_ptr}(value) -> felt {
    const STARK_DIV_2_PLUS_ONE = (-1) / 2 + 1;  // == prime//2 + 1
    const STARK_DIV_2_MIN_ONE = (-1) / 2 - 1;  // == prime//2 - 1
    tempvar is_positive: felt;
    %{
        from starkware.cairo.common.math_utils import as_int
        ids.is_positive = 1 if as_int(ids.value, PRIME) >= 0 else 0
    %}
    if (is_positive != 0) {
        assert_le_felt(value, STARK_DIV_2_MIN_ONE);
        return 1;
    } else {
        assert_le_felt(STARK_DIV_2_PLUS_ONE, value);
        return -1;
    }
}

// From a 128 bit scalar, decomposes it into base (-3) such that
// scalar = sum(digits[i] * (-3)^i for i in [0, 81])
// scalar = sum_p - sum_n
// Where sum_p = sum(digits[i] * (-3)^i for i in [0, 81] if digits[i]==1)
// And sum_n = sum(digits[i] * (-3)^i for i in [0, 81] if digits[i]==-1)
// Returns (abs(sum_p), abs(sum_n), p_sign, n_sign)
func scalar_to_epns{range_check_ptr}(scalar: felt) -> (
    sum_p: felt, sum_n: felt, p_sign: felt, n_sign: felt
) {
    %{
        from garaga.hints.neg_3 import neg_3_base_le, positive_negative_multiplicities
        from starkware.cairo.common.math_utils import as_int
        assert 0 <= ids.scalar < 2**128
        digits = neg_3_base_le(ids.scalar)
        digits = digits + [0] * (82-len(digits))
        i=1 # Loop init
    %}

    tempvar d0;
    %{ ids.d0 = digits[0] %}

    if (d0 != 0) {
        if (d0 == 1) {
            tempvar sum_p = 1;
            tempvar sum_n = 0;
            tempvar pow3 = -3;
        } else {
            tempvar sum_p = 0;
            tempvar sum_n = 1;
            tempvar pow3 = -3;
        }
    } else {
        tempvar sum_p = 0;
        tempvar sum_n = 0;
        tempvar pow3 = -3;
    }

    loop:
    let pow3 = [ap - 1];
    let sum_n = [ap - 2];
    let sum_p = [ap - 3];
    %{ memory[ap] = 1 if i == 82 else 0 %}
    jmp end if [ap] != 0, ap++;

    %{ i+=1 %}

    tempvar di;
    %{ ids.di = digits[i-1] %}
    if (di != 0) {
        if (di == 1) {
            tempvar sum_p = sum_p + pow3;
            tempvar sum_n = sum_n;
            tempvar pow3 = pow3 * (-3);
            jmp loop;
        } else {
            tempvar sum_p = sum_p;
            tempvar sum_n = sum_n + pow3;
            tempvar pow3 = pow3 * (-3);
            jmp loop;
        }
    } else {
        tempvar sum_p = sum_p;
        tempvar sum_n = sum_n;
        tempvar pow3 = pow3 * (-3);
        jmp loop;
    }

    end:
    let pow3 = [ap - 2];
    let sum_n = [ap - 3];
    let sum_p = [ap - 4];
    assert pow3 = (-3) ** 82;  //

    // %{
    //     from starkware.cairo.common.math_utils import as_int
    //     print(f"{as_int(ids.sum_p, PRIME)=}")
    //     print(f"{as_int(ids.sum_n, PRIME)=}")
    // %}
    assert scalar = sum_p - sum_n;

    let p_sign = sign(sum_p);
    let n_sign = sign(sum_n);

    return (p_sign * sum_p, n_sign * sum_n, p_sign, n_sign);
}

func felt_to_UInt384{range_check96_ptr: felt*}(x: felt) -> (res: UInt384) {
    let d0 = [range_check96_ptr];
    let d1 = [range_check96_ptr + 1];
    let d2 = [range_check96_ptr + 2];
    %{
        from garaga.hints.io import bigint_split
        limbs = bigint_split(ids.x, 4, 2 ** 96)
        assert limbs[3] == 0
        ids.d0, ids.d1, ids.d2 = limbs[0], limbs[1], limbs[2]
    %}
    assert [range_check96_ptr + 3] = STARK_MIN_ONE_D2 - d2;
    assert x = d0 + d1 * 2 ** 96 + d2 * 2 ** 192;
    if (d2 == STARK_MIN_ONE_D2) {
        // Take advantage of Cairo prime structure. STARK_MIN_ONE = 0 + 0 * BASE + stark_min_1_d2 * (BASE)**2.
        assert d0 = 0;
        assert d1 = 0;
        tempvar range_check96_ptr = range_check96_ptr + 4;
        return (res=UInt384(d0, d1, d2, 0));
    } else {
        tempvar range_check96_ptr = range_check96_ptr + 4;
        return (res=UInt384(d0, d1, d2, 0));
    }
}

func run_modulo_circuit_basic{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(
    p: UInt384,
    add_offsets_ptr: felt*,
    add_n: felt,
    mul_offsets_ptr: felt*,
    mul_n: felt,
    input_len: felt,
    n_assert_eq: felt,
) {
    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=add_n
    );

    assert mul_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=mul_n
    );

    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], ids.add_n),
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners["mul_mod_builtin"], ids.mul_n),
        )
    %}

    let range_check96_ptr = range_check96_ptr + (input_len + add_n + mul_n - n_assert_eq) * N_LIMBS;
    let add_mod_ptr = &add_mod_ptr[add_n];
    let mul_mod_ptr = &mul_mod_ptr[mul_n];
    return ();
}
