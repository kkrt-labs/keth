from ethereum_types.numeric import U256

func test__ap_accessible() {
    tempvar x = 100;
    %{ assert memory[ap-1] == 100; %}
    ret;
}

func test__pc_accessible() {
    %{ x = pc %}
    ret;
}

func test__fp_accessible() {
    alloc_locals;
    local x = 100;
    %{ assert memory[fp] == 100; %}
    ret;
}

func test__assign_tempvar_ids_variable() {
    tempvar x;
    %{ ids.x = 100; %}

    assert x = 100;
    ret;
}

func test__assign_local_unassigned_variable() {
    alloc_locals;
    local x: felt;
    %{ ids.x = 3; %}

    assert x = 3;
    ret;
}

func test__assign_already_assigned_variable() {
    alloc_locals;
    local x = 3;
    %{ ids.x = 100; %}

    assert x = 3;
    ret;
}

func test__assign_memory() {
    tempvar x;
    %{ memory[ap-1] = 100; %}

    assert x = 100;
    ret;
}

func test__serialize(n: U256) {
    %{ assert serialize(ids.n) == 100; %}
    ret;
}
