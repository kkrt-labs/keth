from starkware.cairo.common.memcpy import memcpy
from starkware.cairo.common.math import assert_not_equal

// Header prepended to each task's output
// by the simple_bootloader and expected by run_bootloader.
struct TaskOutputHeader {
    size: felt,  // Size including this header + actual output
    program_hash: felt,
}

// Expected public outputs for each Keth segment.
struct KethInitOutput {
    // Commitment to the inputs received by `body`.
    body_commitment_low: felt,
    body_commitment_high: felt,
    // Commitment to the inputs received by `teardown`.
    teardown_commitment_low: felt,
    teardown_commitment_high: felt,
}

struct KethBodyOutput {
    // Commitment to the inputs received by this `body` chunk.
    input_commitment_low: felt,
    input_commitment_high: felt,
    // Commitment to the outputs produced by this `body` chunk (state after its transactions).
    post_exec_commitment_low: felt,
    post_exec_commitment_high: felt,
}

struct KethTeardownOutput {
    // Commitment of inputs it expected from `init`.
    init_args_commitment_check_low: felt,
    init_args_commitment_check_high: felt,
    // Commitment of inputs it expected from the last `body` chunk.
    body_args_commitment_check_low: felt,
    body_args_commitment_check_high: felt,
}

// Core Keth STF Aggregator logic.
// Verifies the consistency of commitments between Keth segments.
// Outputs the segment data in the format expected by ApplicativeBootloader for comparison.
// @param taken as hint inputs:
//     program_input = {
//     "keth_segment_outputs": [ [init_out], [body1_out], ..., [bodyN_out], [teardown_out] ],
//     "keth_segment_program_hashes": { "init": H_init, "body": H_body, "teardown": H_teardown },
//     "n_body_chunks": N
// }
func aggregator{output_ptr: felt*, range_check_ptr}() {
    alloc_locals;

    // Number of body chunks executed.
    local n_body_chunks: felt;
    // Program hashes of the Keth segments.
    local init_program_hash: felt;
    local body_program_hash: felt;
    local teardown_program_hash: felt;

    // Pointers to the *serialized* actual outputs of each segment.
    local serialized_init_output: felt*;
    local serialized_body_outputs: felt**;
    local serialized_teardown_output: felt*;

    %{aggregator_inputs%}

    with_attr error_message("AssertionError: Must have at least one body chunk") {
        assert_not_equal(n_body_chunks, 0);
    }

    let init_output: KethInitOutput* = cast(serialized_init_output, KethInitOutput*);
    let teardown_output: KethTeardownOutput* = cast(
        serialized_teardown_output, KethTeardownOutput*
    );

    // --- Verify Commitments ---
    // 1. Check init output links to the first body input
    let first_body_output: KethBodyOutput* = cast(serialized_body_outputs[0], KethBodyOutput*);
    assert init_output.body_commitment_low = first_body_output.input_commitment_low;
    assert init_output.body_commitment_high = first_body_output.input_commitment_high;

    // 2. Check body chunk links recursively/iteratively
    // Only check internal links if there are more than 1 body chunk
    if (n_body_chunks != 1) {
        check_body_chunk_links(
            body_outputs_ptr_array=serialized_body_outputs,
            current_chunk_index=0,
            n_body_chunks=n_body_chunks,
        );
    }

    // 3. Check last body output links to teardown input
    let last_body_output: KethBodyOutput* = cast(
        serialized_body_outputs[n_body_chunks - 1], KethBodyOutput*
    );
    assert last_body_output.post_exec_commitment_low = teardown_output.body_args_commitment_check_low;
    assert last_body_output.post_exec_commitment_high = teardown_output.body_args_commitment_check_high;

    // 4. Check init output links to teardown input
    assert init_output.teardown_commitment_low = teardown_output.init_args_commitment_check_low;
    assert init_output.teardown_commitment_high = teardown_output.init_args_commitment_check_high;

    // --- Construct Output ---
    // Write the output in the format expected by ApplicativeBootloader's memcpy check.
    // This mimics the output of `run_bootloader` for plain tasks.

    let output_ptr = write_segment_output(
        output_ptr=output_ptr,
        program_hash=init_program_hash,
        serialized_output_data=serialized_init_output,
        output_data_size=KethInitOutput.SIZE,
    );

    let output_ptr = write_body_segment_outputs(
        output_ptr=output_ptr,
        program_hash=body_program_hash,
        serialized_body_outputs_array=serialized_body_outputs,
        n_body_chunks=n_body_chunks,
        current_chunk_index=0,
    );

    let output_ptr = write_segment_output(
        output_ptr=output_ptr,
        program_hash=teardown_program_hash,
        serialized_output_data=serialized_teardown_output,
        output_data_size=KethTeardownOutput.SIZE,
    );

    return ();
}

// @notice Helper function to recursively check links between body chunks.
// @param body_outputs_ptr_array: Array of pointers to serialized KethBodyOutput
// @param current_chunk_index: Index of the current body chunk
// @param n_body_chunks: Total number of body chunks
func check_body_chunk_links(
    body_outputs_ptr_array: felt**, current_chunk_index: felt, n_body_chunks: felt
) {
    alloc_locals;

    // Base case: If current_chunk_index reaches the second-to-last chunk,
    // we've checked all links up to n_body_chunks-1 -> n_body_chunks.
    if (current_chunk_index == n_body_chunks - 1) {
        return ();
    }

    let current_body_output: KethBodyOutput* = cast(
        body_outputs_ptr_array[current_chunk_index], KethBodyOutput*
    );
    let next_body_output: KethBodyOutput* = cast(
        body_outputs_ptr_array[current_chunk_index + 1], KethBodyOutput*
    );

    // Assert: Post-execution commitment of current chunk matches initial args of next chunk
    assert current_body_output.post_exec_commitment_low = next_body_output.input_commitment_low;
    assert current_body_output.post_exec_commitment_high = next_body_output.input_commitment_high;

    check_body_chunk_links(
        body_outputs_ptr_array=body_outputs_ptr_array,
        current_chunk_index=current_chunk_index + 1,
        n_body_chunks=n_body_chunks,
    );
    return ();
}

// @notice Helper function to write a single segment's output (header + data)
// @returns the updated output pointer.
func write_segment_output(
    output_ptr: felt*, program_hash: felt, serialized_output_data: felt*, output_data_size: felt
) -> felt* {
    alloc_locals;

    // Calculate total size for this segment's entry
    let header_size = TaskOutputHeader.SIZE;
    let total_size = header_size + output_data_size;

    // Write TaskOutputHeader
    assert [cast(output_ptr, TaskOutputHeader*)] = TaskOutputHeader(
        size=total_size, program_hash=program_hash
    );
    let header_end_ptr = output_ptr + header_size;

    // Write the actual serialized output data
    memcpy(dst=header_end_ptr, src=serialized_output_data, len=output_data_size);
    let data_end_ptr = header_end_ptr + output_data_size;

    return data_end_ptr;
}

// @notice Helper function to recursively write all body segment outputs
// @returns the updated output pointer.
func write_body_segment_outputs(
    output_ptr: felt*,
    program_hash: felt,
    serialized_body_outputs_array: felt**,
    n_body_chunks: felt,
    current_chunk_index: felt,
) -> felt* {
    alloc_locals;

    // Base case: all body chunks written
    if (current_chunk_index == n_body_chunks) {
        return output_ptr;
    }

    // Get pointer to the current body chunk's serialized output
    local current_body_output_ptr: felt* = serialized_body_outputs_array[current_chunk_index];

    // Write the current body segment's output
    let updated_output_ptr = write_segment_output(
        output_ptr=output_ptr,
        program_hash=program_hash,
        serialized_output_data=current_body_output_ptr,
        output_data_size=KethBodyOutput.SIZE,
    );

    // Recursive call for the next body chunk
    return write_body_segment_outputs(
        output_ptr=updated_output_ptr,
        program_hash=program_hash,
        serialized_body_outputs_array=serialized_body_outputs_array,
        n_body_chunks=n_body_chunks,
        current_chunk_index=current_chunk_index + 1,
    );
}
