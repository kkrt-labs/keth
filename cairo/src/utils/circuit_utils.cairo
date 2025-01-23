from starkware.cairo.common.cairo_builtins import PoseidonBuiltin

const N_LIMBS = 4;

func hash_full_transcript_and_get_Z_3_LIMBS{poseidon_ptr: PoseidonBuiltin*}(
    limbs_ptr: felt*, n: felt
) -> (_s0: felt, _s1: felt, _s2: felt) {
    alloc_locals;
    local BASE = 2 ** 96;

    let elements_end = &limbs_ptr[n * N_LIMBS];

    tempvar elements = limbs_ptr;
    tempvar pos_ptr = cast(poseidon_ptr, felt*);

    loop:
    if (nondet %{ ids.elements_end - ids.elements >= 6*ids.N_LIMBS %} != 0) {
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
