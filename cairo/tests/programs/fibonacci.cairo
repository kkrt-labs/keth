%builtins output

func main{
    output_ptr: felt*,
}() {
    alloc_locals;

    tempvar a;
    tempvar b;
    tempvar n;
    %{ ids.a, ids.b, ids.n = program_input; %}
    let result: felt = fib(a, b, n);

    // Make sure the 10th Fibonacci number is 144.
    assert [output_ptr] = result;
    let output_ptr = output_ptr + 1;
    return ();
}

func fib(a, b, n) -> (res: felt) {
    jmp fib_body if n != 0;
    tempvar result = b;
    return (b,);

    fib_body:
    tempvar y = a + b;
    return fib(b, y, n - 1);
}
