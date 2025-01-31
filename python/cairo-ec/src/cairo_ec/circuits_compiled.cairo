from starkware.cairo.common.cairo_builtins import UInt384, ModBuiltin
from starkware.cairo.lang.compiler.lib.registers import get_fp_and_pc

func add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_offsets_ptr = pc + (mul_offsets - pc_label);
    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;

    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    assert add_mod_ptr[0] = ModBuiltin(
        p=[p], values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );

    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner

        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners['add_mod_builtin'], 1),
            mul_mod=None,
        )
    %}

    let range_check96_ptr = range_check96_ptr + 12;

    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE * 1;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:
    dw 0;
    dw 4;
    dw 8;

    mul_offsets:
}

func sub{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_offsets_ptr = pc + (mul_offsets - pc_label);
    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;

    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    assert add_mod_ptr[0] = ModBuiltin(
        p=[p], values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=1
    );

    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner

        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners['add_mod_builtin'], 1),
            mul_mod=None,
        )
    %}

    let range_check96_ptr = range_check96_ptr + 12;

    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE * 1;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:
    dw 8;
    dw 4;
    dw 0;

    mul_offsets:
}

func mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_offsets_ptr = pc + (mul_offsets - pc_label);
    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;

    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    assert mul_mod_ptr[0] = ModBuiltin(
        p=[p], values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=1
    );

    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner

        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=None,
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners['mul_mod_builtin'], 1),
        )
    %}

    let range_check96_ptr = range_check96_ptr + 12;
    let mul_mod_ptr = mul_mod_ptr + ModBuiltin.SIZE * 1;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:

    mul_offsets:
    dw 0;
    dw 4;
    dw 8;
}

func div{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_offsets_ptr = pc + (mul_offsets - pc_label);
    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;

    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    assert mul_mod_ptr[0] = ModBuiltin(
        p=[p], values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=1
    );

    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner

        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=None,
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners['mul_mod_builtin'], 1),
        )
    %}

    let range_check96_ptr = range_check96_ptr + 12;
    let mul_mod_ptr = mul_mod_ptr + ModBuiltin.SIZE * 1;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:

    mul_offsets:
    dw 8;
    dw 4;
    dw 0;
}

func diff_ratio{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_offsets_ptr = pc + (mul_offsets - pc_label);
    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;

    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    assert add_mod_ptr[0] = ModBuiltin(
        p=[p], values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=2
    );
    assert mul_mod_ptr[0] = ModBuiltin(
        p=[p], values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=1
    );

    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner

        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners['add_mod_builtin'], 2),
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners['mul_mod_builtin'], 1),
        )
    %}

    let range_check96_ptr = range_check96_ptr + 20;

    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE * 2;
    let mul_mod_ptr = mul_mod_ptr + ModBuiltin.SIZE * 1;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:
    dw 8;
    dw 4;
    dw 0;
    dw 12;
    dw 4;
    dw 0;

    mul_offsets:
    dw 16;
    dw 12;
    dw 8;
}

func sum_ratio{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    x: UInt384*, y: UInt384*, p: UInt384*
) -> UInt384* {
    let (_, pc) = get_fp_and_pc();

    pc_label:
    let add_offsets_ptr = pc + (add_offsets - pc_label);
    let mul_offsets_ptr = pc + (mul_offsets - pc_label);
    assert [range_check96_ptr + 0] = x.d0;
    assert [range_check96_ptr + 1] = x.d1;
    assert [range_check96_ptr + 2] = x.d2;
    assert [range_check96_ptr + 3] = x.d3;

    assert [range_check96_ptr + 4] = y.d0;
    assert [range_check96_ptr + 5] = y.d1;
    assert [range_check96_ptr + 6] = y.d2;
    assert [range_check96_ptr + 7] = y.d3;

    assert add_mod_ptr[0] = ModBuiltin(
        p=[p], values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=add_offsets_ptr, n=2
    );
    assert mul_mod_ptr[0] = ModBuiltin(
        p=[p], values_ptr=cast(range_check96_ptr, UInt384*), offsets_ptr=mul_offsets_ptr, n=1
    );

    %{
        from starkware.cairo.lang.builtins.modulo.mod_builtin_runner import ModBuiltinRunner

        assert builtin_runners["add_mod_builtin"].instance_def.batch_size == 1
        assert builtin_runners["mul_mod_builtin"].instance_def.batch_size == 1

        ModBuiltinRunner.fill_memory(
            memory=memory,
            add_mod=(ids.add_mod_ptr.address_, builtin_runners['add_mod_builtin'], 2),
            mul_mod=(ids.mul_mod_ptr.address_, builtin_runners['mul_mod_builtin'], 1),
        )
    %}

    let range_check96_ptr = range_check96_ptr + 20;

    let add_mod_ptr = add_mod_ptr + ModBuiltin.SIZE * 2;
    let mul_mod_ptr = mul_mod_ptr + ModBuiltin.SIZE * 1;

    return cast(range_check96_ptr - 4, UInt384*);

    add_offsets:
    dw 0;
    dw 4;
    dw 8;
    dw 0;
    dw 4;
    dw 12;

    mul_offsets:
    dw 16;
    dw 12;
    dw 8;
}
