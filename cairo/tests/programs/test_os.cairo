from programs.os import main

from src.model import model

func test_os{output_ptr: felt*}() {
    main();

    return ();
}

func test_block() -> model.Block* {
    tempvar block: model.Block*;
    %{ block %}
    return block;
}
