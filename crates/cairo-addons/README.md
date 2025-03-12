# Cairo Addons

Rust bindings for Cairo VM with support for:

- Running programs in proof mode, with python objects as inputs
- Running pythonic hints inside the Rust VM

## Running a Program in Proof Mode

The `run_proof_mode` function provides a high-level interface for running a
Cairo program in proof mode.

The execution does not support the execution of trace hints
(`%{logger.trace ... %}`), which will be skipped to avoid slowing down the runs.

```rust
pub fn run_proof_mode(
    entrypoint: String,
    public_inputs: PyObject,
    private_inputs: PyObject,
    compiled_program_path: String,
    output_dir: PathBuf,
) -> PyResult<()>
```

### Parameters

- `entrypoint`: Function name in the Cairo program to execute
- `public_inputs`: Python dictionary containing public inputs
- `private_inputs`: Python dictionary containing private inputs
- `compiled_program_path`: Path to the compiled Cairo program JSON
- `output_dir`: Directory where proof artifacts will be saved

### Python Usage

```python
from cairo_addons.vm import run_proof_mode

run_proof_mode(
    entrypoint="main",
    public_inputs=public_inputs_dict,
    private_inputs=private_inputs_dict,
    compiled_program_path="./build/main.json",
    output_dir="./output"
)
```

### Output Files

- `trace.bin`: Binary trace of program execution
- `memory.bin`: Memory dump after execution
- `air_public_input.json`: Public inputs for the AIR
- `air_private_input.json`: Private inputs for the AIR

## CairoRunner for Tests

The `PyCairoRunner` class provides a Python interface to the Cairo VM for
testing:

### Initialization

`enable_traces` is a flag that is used to control whether `logger.trace` hints
are executed. If enabled, this will considerably slow down the execution.

```python
from cairo_addons.vm import CairoRunner

runner = CairoRunner(
    program=program,
    layout="all_cairo",
    proof_mode=False,
    enable_traces=True
)
```

## Pythonic Hint Execution

The `PythonicHintExecutor` enables execution of Python code within Cairo hints.
Notably, we developed an API that is transparent with how we interact with the
Python Cairo VM.

This means that we can:

- Stop during the execution of a program using `breakpoint()`
- Access `memory`, `segments`, `dict_manager`, `ids` data inside hints, like we
  would on the Python VM
- Added are global variables that are available to all hints, like a `logger`
  object that, if enabled, can be used to print execution traces; as well as
  `gen_arg` and `serialize` functions that can be used to convert between Cairo
  and Python types.

During execution, the VM passes hints to the hint processor. If a hint is not
registered (meaning, we can't find a Rust function that matches the hint's
content), it's executed using Python Interpreter inside the Rust VM.

Serializing and writing to stdout during the execution of hints has performance
impacts; which is why, unless `enable_traces` is set to `True`, we do not
execute hints containing `logger.trace`.
