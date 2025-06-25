# Test Fixes Summary

## Issues Fixed

### 1. Missing patch_get_default_program() Context

Added `patch_get_default_program()` context to all tests that use
`mock_all_programs`:

- `test_trace_command_auto_detect_chain_id`
- `test_trace_command_body_step_with_params`
- `test_trace_command_with_explicit_chain_id`
- `test_trace_command_with_cairo_pie`
- `test_trace_command_mpt_diff_step_with_params`
- `test_e2e_command_main_step`
- `test_e2e_command_body_step_filename`
- `test_e2e_command_mpt_diff_step_filename`
- `test_trace_then_prove_workflow`
- `test_full_e2e_workflow`

### 2. Fixed Incorrect Patch Path

Changed `"keth_cli.run_generate_trace"` to
`"keth_cli.orchestration.run_generate_trace"` in:

- `test_generate_ar_inputs_command_body_chunking`

### 3. Updated Test Expectations for Correct Transaction Count

The test data file `test_data/22615247.json` contains 26 transactions, not 8.
Updated all generate_ar_inputs tests:

- `test_generate_ar_inputs_command_basic`: Changed from 21 to 25 calls (chunk
  size 5)
- `test_generate_ar_inputs_command_with_options`: Added assertion for 28 calls
  (chunk size 3)
- `test_generate_ar_inputs_command_body_chunking`: Updated comments to reflect
  26 transactions
- `test_generate_ar_inputs_filename_consistency`: Added assertion for 22 calls
  (chunk size 10)
- `test_generate_ar_inputs_command_with_cairo_pie`: Added assertion for 25 calls
  (chunk size 5)

### 4. Fixed Filename Pattern Matching

Added `"_mpt_diff_"` to the filename pattern check in
`test_generate_ar_inputs_filename_consistency` to account for MPT diff step
files.

## Summary

All tests should now pass with the correct:

- Mock program patches applied consistently
- Correct import paths for patching
- Accurate transaction counts based on the actual test data
- Complete filename pattern matching
