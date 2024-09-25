from programs.os import main

from src.model import model

func test_os{output_ptr: felt*}() {
    main();

    return ();
}

func test_block_header() -> model.BlockHeader* {
    tempvar block_header: model.BlockHeader*;
    %{ block_header %}
    return block_header;
}
