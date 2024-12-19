from starkware.cairo.common.cairo_builtins import UInt384
from starkware.cairo.common.cairo_builtins import ModBuiltin
from starkware.cairo.common.registers import get_fp_and_pc
from ethereum.utils.numeric import divmod

const POW_2_32 = 2 ** 32;
const POW_2_64 = 2 ** 64;
const POW_2_96 = 2 ** 96;

// Compute u512 mod p, where u512 = high * 2^256 + low
// Each high/low limb is 32 bits big and passed in BE
func u512_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    low: (v0: felt, v1: felt, v2: felt, v3: felt, v4: felt, v5: felt, v6: felt, v7: felt),
    high: (v0: felt, v1: felt, v2: felt, v3: felt, v4: felt, v5: felt, v6: felt, v7: felt),
    p: UInt384,
) -> (result: UInt384) {
    let (_, pc) = get_fp_and_pc();

    pc_labelx:
    let add_offsets_ptr = pc + (add_offsets - pc_labelx);
    let mul_offsets_ptr = pc + (mul_offsets - pc_labelx);

    // High limbs.
    assert [range_check96_ptr] = high.v7 + high.v6 * POW_2_32_252 + high.v5 * POW_2_64_252;
    assert [range_check96_ptr + 1] = high.v4 + high.v3 * POW_2_32_252 + high.v2 * POW_2_64_252;
    assert [range_check96_ptr + 2] = high.v1 + high.v0 * POW_2_32_252;
    assert [range_check96_ptr + 3] = 0;

    // Shift Limbs.
    assert [range_check96_ptr + 4] = 0;
    assert [range_check96_ptr + 5] = 0;
    assert [range_check96_ptr + 6] = 0x10000000000000000;
    assert [range_check96_ptr + 7] = 0;

    // Low limbs.
    assert [range_check96_ptr + 8] = low.v7 + low.v6 * POW_2_32_252 + low.v5 * POW_2_64_252;
    assert [range_check96_ptr + 9] = low.v4 + low.v3 * POW_2_32_252 + low.v2 * POW_2_64_252;
    assert [range_check96_ptr + 10] = low.v1 + low.v0 * POW_2_32_252;
    assert [range_check96_ptr + 11] = 0;

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    assert mul_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=1
    );
    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 1),
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners["mul_mod_builtin"], 1),
        )
    %}
    let range_check96_ptr = range_check96_ptr + 20;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    let mul_mod_ptr = mul_mod_ptr + ModBuiltin.SIZE;
    return (result=[cast(range_check96_ptr - 4, UInt384*)]);

    mul_offsets:
    // Compute High * Shift
    dw 0;  // [High]
    dw 4;  // [Shift]
    dw 12;  // [High * Shift]

    // Computes [Low + High * Shift]
    add_offsets:
    dw 8;  // Low
    dw 12;  // [High * Shift]
    dw 16;  // [Low + High * Shift]
}

// Compute X + Y mod p.
func add_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*}(
    x: UInt384, y: UInt384, p: UInt384
) -> (x_plus_y: UInt384) {
    let (_, pc) = get_fp_and_pc();

    pc_labelx:
    let add_offsets_ptr = pc + (add_offsets - pc_labelx);

    // X limbs (offset 0)
    assert [range_check96_ptr] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    // Y limbs (offset 4)
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 1),
            mul_mod=None,
        )
    %}

    let range_check96_ptr = range_check96_ptr + 12;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    return (x_plus_y=[cast(range_check96_ptr - 4, UInt384*)]);

    add_offsets:
    // Instruction : assert 0 + 4 == 8
    dw 0;  // X
    dw 4;  // Y
    dw 8;  // X+Y
}

// Compute X - Y mod p.
func sub_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*}(
    x: UInt384, y: UInt384, p: UInt384
) -> (x_minus_y: UInt384) {
    let (_, pc) = get_fp_and_pc();

    pc_labelx:
    let add_offsets_ptr = pc + (add_offsets - pc_labelx);

    // X limbs (offset 0)
    assert [range_check96_ptr] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;
    // Y limbs (offset 4)
    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 1),
            mul_mod=None,
        )
    %}

    let range_check96_ptr = range_check96_ptr + 12;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    return (x_minus_y=[cast(range_check96_ptr - 4, UInt384*)]);

    add_offsets:
    // Instruction : assert 4 + 8 == 0
    // 8 is unallocated, so the assert is Y + ?  == X
    // => ? == X - Y, at offset 8.
    dw 4;  // Y
    dw 8;  // X-Y
    dw 0;
}

// Assert X == 0 mod p.
func assert_zero_mod_P{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*}(x: UInt384, p: UInt384) {
    let (_, pc) = get_fp_and_pc();

    pc_labelx:
    let add_offsets_ptr = pc + (add_offsets - pc_labelx);

    // Const 0.
    assert [range_check96_ptr] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    // X limbs.
    assert [range_check96_ptr + 4] = x.d0;
    assert [range_check96_ptr + 5] = x.d1;
    assert [range_check96_ptr + 6] = x.d2;
    assert [range_check96_ptr + 7] = x.d3;

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 1),
            mul_mod=None,
        )
    %}
    let range_check96_ptr = range_check96_ptr + 8;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    return ();

    add_offsets:
    // Instruction (offsets) : assert 0 + 4 == 0
    // <=> 0 + X == 0 mod p. => X == 0 mod p.
    dw 0;  // 0
    dw 4;  // X
    dw 0;  // 0
}

// Assert X != 0 mod p.
func assert_not_zero_mod_P{range_check96_ptr: felt*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384, p: UInt384
) {
    let (_, pc) = get_fp_and_pc();

    pc_labelx:
    let mul_offsets_ptr = pc + (mul_offsets - pc_labelx);

    // Const 1. (offset 0)
    assert [range_check96_ptr] = 1;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    // X limbs (offset 4)
    assert [range_check96_ptr + 4] = x.d0;
    assert [range_check96_ptr + 5] = x.d1;
    assert [range_check96_ptr + 6] = x.d2;
    assert [range_check96_ptr + 7] = x.d3;

    // X^-1 (offset 8)
    let x_inv_d0 = [range_check96_ptr + 8];
    let x_inv_d1 = [range_check96_ptr + 9];
    let x_inv_d2 = [range_check96_ptr + 10];
    let x_inv_d3 = [range_check96_ptr + 11];

    %{
        from garaga.hints.io import bigint_split, bigint_pack
        p = bigint_pack(ids.p, 4, 2**96)
        x = bigint_pack(ids.x, 4, 2**96)
        x_inv = pow(x, -1, p)
        limbs = bigint_split(x_inv)
        ids.x_inv_d0 = limbs[0]
        ids.x_inv_d1 = limbs[1]
        ids.x_inv_d2 = limbs[2]
        ids.x_inv_d3 = limbs[3]
    %}

    assert mul_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=1
    );

    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=None,
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners["mul_mod_builtin"], 1),
        )
    %}
    let range_check96_ptr = range_check96_ptr + 12;
    let mul_mod_ptr = mul_mod_ptr + ModBuiltin.SIZE;
    return ();

    // Assert X*X_inv == 1 (hints will fill X_inv and proof will assert X*X_inv == 1).
    // If X_inv does not exists, no valid proof can be generated.
    mul_offsets:
    // Instruction (offsets) : assert 4 * 8 == 0
    dw 4;  // X
    dw 8;  // X_inv
    dw 0;  // 0
}

// Returns 1 if X == 0 mod p, 0 otherwise.
func is_zero_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384, p: UInt384
) -> (res: felt) {
    %{
        from garaga.hints.io import bigint_pack
        x = bigint_pack(ids.x, 4, 2**96)
        p = bigint_pack(ids.p, 4, 2**96)
    %}
    if (nondet %{ x % p == 0 %} != 0) {
        assert_zero_mod_P(x, p);
        return (res=1);
    } else {
        assert_not_zero_mod_P(x, p);
        return (res=0);
    }
}

// Assert X == Y mod p by asserting Y - X == 0
func assert_eq_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*}(
    x: UInt384, y: UInt384, p: UInt384
) {
    let (_, pc) = get_fp_and_pc();

    pc_labelx:
    let add_offsets_ptr = pc + (add_offsets - pc_labelx);

    // Const 0. (offset 0)
    assert [range_check96_ptr] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    // X limbs (offset 4)
    assert [range_check96_ptr + 4] = x.d0;
    assert [range_check96_ptr + 5] = x.d1;
    assert [range_check96_ptr + 6] = x.d2;
    assert [range_check96_ptr + 7] = x.d3;
    // Y limbs (offset 8)
    assert [range_check96_ptr + 8] = y.d0;
    assert [range_check96_ptr + 9] = y.d1;
    assert [range_check96_ptr + 10] = y.d2;
    assert [range_check96_ptr + 11] = y.d3;

    // Builtin results :
    // (- X) (offset 12)
    // (Y - X) (offset 16)

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=2
    );
    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 2),
            mul_mod=None,
        )
    %}
    let range_check96_ptr = range_check96_ptr + 16;
    let add_mod_ptr = add_mod_ptr + 2 * ModBuiltin.SIZE;
    return ();

    // Compute 0 - X (X + (-X) = 0)
    add_offsets:
    dw 4;
    dw 12;  // - X
    dw 0;
    // Compute - X + Y and assert == 0
    dw 12;  // - X
    dw 8;  // Y
    dw 0;
}

// assert X != Y mod p by asserting (X-Y) != 0
func assert_neq_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384, y: UInt384, p: UInt384
) {
    let (_, pc) = get_fp_and_pc();

    pc_labelx:
    let add_offsets_ptr = pc + (add_offsets - pc_labelx);
    let mul_offsets_ptr = pc + (mul_offsets - pc_labelx);

    // Const 1. (0)
    assert [range_check96_ptr] = 1;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    // X limbs. (4)
    assert [range_check96_ptr + 4] = x.d0;
    assert [range_check96_ptr + 5] = x.d1;
    assert [range_check96_ptr + 6] = x.d2;
    assert [range_check96_ptr + 7] = x.d3;
    // Y limbs. (8)
    assert [range_check96_ptr + 8] = y.d0;
    assert [range_check96_ptr + 9] = y.d1;
    assert [range_check96_ptr + 10] = y.d2;
    assert [range_check96_ptr + 11] = y.d3;

    // [X-Y] (12)

    // [X-Y]^-1 (16)
    let diff_inv_d0 = [range_check96_ptr + 16];
    let diff_inv_d1 = [range_check96_ptr + 17];
    let diff_inv_d2 = [range_check96_ptr + 18];
    let diff_inv_d3 = [range_check96_ptr + 19];

    %{
        from garaga.hints.io import bigint_split, bigint_pack
        p = bigint_pack(ids.p, 4, 2**96)
        x = bigint_pack(ids.x, 4, 2**96)
        y = bigint_pack(ids.y, 4, 2**96)
        diff = (x - y) % p
        diff_inv = pow(diff, -1, p)
        limbs = bigint_split(diff_inv)
        ids.diff_inv_d0 = limbs[0]
        ids.diff_inv_d1 = limbs[1]
        ids.diff_inv_d2 = limbs[2]
        ids.diff_inv_d3 = limbs[3]
    %}

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    assert mul_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=1
    );
    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 1),
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners["mul_mod_builtin"], 1),
        )
    %}
    let range_check96_ptr = range_check96_ptr + 20;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    let mul_mod_ptr = mul_mod_ptr + ModBuiltin.SIZE;
    return ();

    // Compute X - Y <=> Y + (X-Y) == X
    add_offsets:
    dw 8;  // Y
    dw 12;  // X - Y
    dw 4;  // X

    mul_offsets:
    // Assert (X-Y)*(X-Y)^-1 == 1 ==> (X-Y) != 0
    dw 12;  // [X-Y]
    dw 16;  // [X-Y]^-1
    dw 0;
}

// Returns 1 if X == Y mod p, 0 otherwise.
func is_eq_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384, y: UInt384, p: UInt384
) -> (res: felt) {
    %{
        from garaga.hints.io import bigint_pack
        x = bigint_pack(ids.x, 4, 2**96)
        y = bigint_pack(ids.y, 4, 2**96)
        p = bigint_pack(ids.p, 4, 2**96)
    %}

    if (nondet %{ x % p == y % p %} != 0) {
        assert_eq_mod_p(x, y, p);
        return (res=1);
    } else {
        assert_neq_mod_p(x, y, p);
        return (res=0);
    }
}

// Assert X == - Y mod p by asserting X + Y == 0
func assert_opposite_mod_p{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*}(
    x: UInt384, y: UInt384, p: UInt384
) {
    let (_, pc) = get_fp_and_pc();

    pc_labelx:
    let add_offsets_ptr = pc + (add_offsets - pc_labelx);

    // Const 0.
    assert [range_check96_ptr] = 0;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    // X limbs.
    assert [range_check96_ptr + 4] = x.d0;
    assert [range_check96_ptr + 5] = x.d1;
    assert [range_check96_ptr + 6] = x.d2;
    assert [range_check96_ptr + 7] = x.d3;
    // Y limbs.
    assert [range_check96_ptr + 8] = y.d0;
    assert [range_check96_ptr + 9] = y.d1;
    assert [range_check96_ptr + 10] = y.d2;
    assert [range_check96_ptr + 11] = y.d3;

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 1),
            mul_mod=None,
        )
    %}

    let range_check96_ptr = range_check96_ptr + 12;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    return ();

    // Assert X + Y == 0 <=> X == -Y
    add_offsets:
    dw 4;  // X
    dw 8;  // Y
    dw 0;
}

// assert X != -Y mod p by asserting X + Y != 0
func assert_not_opposite_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: UInt384, y: UInt384, p: UInt384) {
    let (_, pc) = get_fp_and_pc();

    pc_labelx:
    let add_offsets_ptr = pc + (add_offsets - pc_labelx);
    let mul_offsets_ptr = pc + (mul_offsets - pc_labelx);

    // Const 1. (0)
    assert [range_check96_ptr] = 1;
    assert [range_check96_ptr + 1] = 0;
    assert [range_check96_ptr + 2] = 0;
    assert [range_check96_ptr + 3] = 0;
    // X limbs. (4)
    assert [range_check96_ptr + 4] = x.d0;
    assert [range_check96_ptr + 5] = x.d1;
    assert [range_check96_ptr + 6] = x.d2;
    assert [range_check96_ptr + 7] = x.d3;
    // Y limbs. (8)
    assert [range_check96_ptr + 8] = y.d0;
    assert [range_check96_ptr + 9] = y.d1;
    assert [range_check96_ptr + 10] = y.d2;
    assert [range_check96_ptr + 11] = y.d3;

    // [X+Y] (12)
    // ...

    // [X+Y]^-1 (16)
    let sum_inv_d0 = [range_check96_ptr + 16];
    let sum_inv_d1 = [range_check96_ptr + 17];
    let sum_inv_d2 = [range_check96_ptr + 18];
    let sum_inv_d3 = [range_check96_ptr + 19];

    %{
        from garaga.hints.io import bigint_split, bigint_pack
        p = bigint_pack(ids.p, 4, 2**96)
        x = bigint_pack(ids.x, 4, 2**96)
        y = bigint_pack(ids.y, 4, 2**96)
        _sum = (x + y) % p
        sum_inv = pow(_sum, -1, p)
        limbs = bigint_split(sum_inv)
        ids.sum_inv_d0 = limbs[0]
        ids.sum_inv_d1 = limbs[1]
        ids.sum_inv_d2 = limbs[2]
        ids.sum_inv_d3 = limbs[3]
    %}

    assert add_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );
    assert mul_mod_ptr[0] = ModBuiltin(
        p=p, values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=1
    );
    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner
        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners["add_mod_builtin"], 1),
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners["mul_mod_builtin"], 1),
        )
    %}
    let range_check96_ptr = range_check96_ptr + 20;
    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE;
    let mul_mod_ptr = mul_mod_ptr + ModBuiltin.SIZE;
    return ();

    // Compute X - Y
    add_offsets:
    dw 4;  // X
    dw 8;  // Y
    dw 12;

    mul_offsets:
    // Assert (X+Y)*(X+Y)^-1 == 1 ==> (X+Y) != 0
    dw 12;  // [X+Y]
    dw 16;  // [X+Y]^-1
    dw 0;
}

// Returns 1 if X == -Y mod p, 0 otherwise.
func is_opposite_mod_p{
    range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*
}(x: UInt384, y: UInt384, p: UInt384) -> (res: felt) {
    %{
        from garaga.hints.io import bigint_pack
        x = bigint_pack(ids.x, 4, 2**96)
        y = bigint_pack(ids.y, 4, 2**96)
        p = bigint_pack(ids.p, 4, 2**96)
    %}
    if (nondet %{ x % p == -y % p %} != 0) {
        assert_opposite_mod_p(x, y, p);
        return (res=1);
    } else {
        assert_not_opposite_mod_p(x, y, p);
        return (res=0);
    }
}
