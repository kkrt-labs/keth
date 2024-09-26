from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.memcpy import memcpy

from src.model import model
from src.utils.eth_transaction import Transaction
from src.utils.rlp import RLP

func test__decode{bitwise_ptr: BitwiseBuiltin*, range_check_ptr}() -> model.Transaction* {
    alloc_locals;
    // Given
    tempvar data_len: felt;
    let (data) = alloc();
    %{
        ids.data_len = len(program_input["data"])
        segments.write_arg(ids.data, program_input["data"])
    %}

    let tx = Transaction.decode(data_len, data);
    return tx;
}

func test__parse_access_list{range_check_ptr}(output_ptr: felt*) {
    alloc_locals;
    // Given
    tempvar data_len: felt;
    let (data) = alloc();
    %{
        ids.data_len = len(program_input["data"])
        segments.write_arg(ids.data, program_input["data"])
    %}

    // Decode the RLP-encoded access list to get the data in the cairo format
    let (items: RLP.Item*) = alloc();
    RLP.decode(items, data_len, data);

    // first level RLP decoding is a list of items. In our case the only item we decoded was the access list.
    // the access list is a list of tuples (address, list(keys)), hence first level RLP decoding
    // is a single item of type list.
    let (local access_list: felt*) = alloc();
    // When
    let access_list_len = Transaction.parse_access_list(
        access_list, items.data_len, cast(items.data, RLP.Item*)
    );

    memcpy(output_ptr, access_list, access_list_len);
    return ();
}

func test__get_tx_type{range_check_ptr}() -> felt {
    alloc_locals;
    // Given
    tempvar data_len: felt;
    let (data) = alloc();
    %{
        ids.data_len = program_input.get("data_len", len(program_input["data"]))
        segments.write_arg(ids.data, program_input["data"])
    %}

    // When
    let tx_type = Transaction.get_tx_type(data_len, data);

    return tx_type;
}
