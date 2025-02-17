from starkware.cairo.common.cairo_builtins import PoseidonBuiltin, UInt384

const N_LIMBS = UInt384.SIZE;

func hash_full_transcript{poseidon_ptr: PoseidonBuiltin*}(limbs_ptr: felt*, n: felt) -> () {
    alloc_locals;
    local BASE = 2 ** 96;

    local elements_end: felt* = limbs_ptr + (n * N_LIMBS);

    tempvar elements = limbs_ptr;
    tempvar pos_ptr = cast(poseidon_ptr, felt*);

    loop:
    let N_LIMBS_HINT = N_LIMBS;
    tempvar has_six_uint384_remaining;
    %{ has_six_uint384_remaining_hint %}
    ap += 1;
    if (has_six_uint384_remaining != 0) {
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

    tempvar has_one_uint384_remaining;
    %{ has_one_uint384_remaining_hint %}
    ap += 1;
    if (has_one_uint384_remaining != 0) {
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

    return ();
}
