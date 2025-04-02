from ethereum_types.numeric import U256, U256Struct
from starkware.cairo.common.alloc import alloc

from cairo_ec.curve.alt_bn128 import alt_bn128
from ethereum.exceptions import ValueError

func test__ap_accessible() {
    tempvar x = 100;
    %{ assert memory[ap-1] == 100 %}
    ret;
}

func test__pc_accessible() {
    %{ x = pc %}
    ret;
}

func test__fp_accessible() {
    alloc_locals;
    local x = 100;
    %{ assert memory[fp] == 100 %}
    ret;
}

func test__assign_tempvar_ids_variable() {
    tempvar x;
    %{ ids.x = 100 %}

    assert x = 100;
    ret;
}

func test__assign_local_unassigned_variable() {
    alloc_locals;
    local x: felt;
    %{ ids.x = 3 %}

    assert x = 3;
    ret;
}

func test__assign_already_assigned_variable_should_fail() {
    alloc_locals;
    local x = 3;
    %{ ids.x = 100 %}
    ret;
}

func test__assign_memory() {
    tempvar x;
    %{ memory[ap-1] = 100 %}

    assert x = 100;
    ret;
}

func test__access_struct_members() {
    tempvar n = U256Struct(100, 200);
    %{
        assert ids.n.low == 100, f"ids.n.low: {ids.n.low}";
        assert ids.n.high == 200, f"ids.n.high: {ids.n.high}";
    %}
    ret;
}

func test__access_struct_members_pointers() {
    tempvar n = new U256Struct(100, 200);
    %{
        assert ids.n.low == 100, f"ids.n.low: {ids.n.low}";
        assert ids.n.high == 200, f"ids.n.high: {ids.n.high}";
    %}
    ret;
}

func test_access_nested_structs() {
    tempvar n = U256(new U256Struct(100, 200));
    %{
        assert ids.n.value.low == 100, f"ids.n.value.low: {ids.n.value.low}";
        assert ids.n.value.high == 200, f"ids.n.value.high: {ids.n.value.high}";
    %}
    ret;
}

func test_access_struct_member_address() {
    tempvar n = U256(new U256Struct(100, 200));
    %{
        assert memory[ids.n.value.address_] == 100, f"memory[ids.n.value.address_]: {memory[ids.n.value.address_]}";
        assert memory[ids.n.value.address_ + 1] == 200, f"memory[ids.n.value.address_ + 1]: {memory[ids.n.value.address_ + 1]}";
    %}
    ret;
}

func test__serialize(n: U256) {
    %{ assert serialize(ids.n) == ids.n.value.low + ids.n.value.high * 2**128 %}
    ret;
}

func test__gen_arg_pointer(n: U256) {
    tempvar x: U256Struct*;
    %{
        from ethereum_types.numeric import U256
        ids.x = gen_arg(U256, serialize(ids.n));
    %}

    assert x.low = n.value.low;
    assert x.high = n.value.high;
    ret;
}

func test__gen_arg_struct(n: U256) {
    tempvar x: U256;
    %{
        from ethereum_types.numeric import U256
        ids.x = gen_arg(U256, serialize(ids.n));
    %}

    assert x.value.low = n.value.low;
    assert x.value.high = n.value.high;
    ret;
}

func test__access_let_felt() {
    let x = 3;
    %{ assert ids.x == 3 %}
    ret;
}

func test__access_let_relocatable() {
    let (x) = alloc();
    %{
        # simple access
        ids.x
    %}
    ret;
}

const MY_CONST = 100;
func test__access_local_const() {
    %{ assert ids.MY_CONST == 100 %}
    ret;
}

func test__access_non_imported_const_should_fail() {
    %{ ids.HALF_SHIFT %}
    ret;
}

func test__access_imported_const() {
    %{ assert ids.ValueError == int.from_bytes('ValueError'.encode("ascii"), "big") %}
    ret;
}
