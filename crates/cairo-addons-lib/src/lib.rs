use crate::vm::hints::HintProcessor;
use bincode::enc::write::Writer;
use cairo_air::verifier::verify_cairo;
use cairo_vm::{
    air_private_input::{AirPrivateInput, PrivateInput},
    cairo_run::{self, write_encoded_memory, write_encoded_trace, CairoRunConfig},
    hint_processor::builtin_hint_processor::dict_manager::DictManager,
    serde::deserialize_program::Identifier,
    types::{
        builtin_name::BuiltinName, exec_scope::ExecutionScopes, layout_name::LayoutName,
        program::Program,
    },
};
use pyo3::{
    prelude::*,
    types::{IntoPyDict, PyDict},
    PyErr,
};
use std::{
    cell::RefCell,
    collections::HashMap,
    ffi::CString,
    fs::File,
    io::{self, Write},
    path::PathBuf,
    rc::Rc,
};
use stwo_cairo_adapter::ExecutionResources as ProverExecutionResources;
use stwo_cairo_prover::{
    prover::{default_prod_prover_parameters, prove_cairo, ProverParameters},
    stwo_prover::core::vcs::blake2_merkle::Blake2sMerkleChannel,
};
use tracing_subscriber::{fmt::format::FmtSpan, EnvFilter};

pub mod vm;

// FileWriter struct for bincode encoding
// From <https://github.com/lambdaclass/cairo-vm/blob/5d7c20880785e1f9edbd73d0d46aeb58d8bced4e/cairo-vm-cli/src/main.rs#L109-L140>
pub struct FileWriter {
    buf_writer: io::BufWriter<File>,
    bytes_written: usize,
}

impl Writer for FileWriter {
    fn write(&mut self, bytes: &[u8]) -> Result<(), bincode::error::EncodeError> {
        self.buf_writer
            .write_all(bytes)
            .map_err(|e| bincode::error::EncodeError::Io { inner: e, index: self.bytes_written })?;

        self.bytes_written += bytes.len();

        Ok(())
    }
}

impl FileWriter {
    fn new(buf_writer: io::BufWriter<File>) -> Self {
        Self { buf_writer, bytes_written: 0 }
    }

    fn flush(&mut self) -> io::Result<()> {
        self.buf_writer.flush()
    }
}

#[derive(serde::Serialize)]
struct SerializableAirPrivateInput {
    builtins: HashMap<BuiltinName, Vec<PrivateInput>>,
}

impl From<AirPrivateInput> for SerializableAirPrivateInput {
    fn from(input: AirPrivateInput) -> Self {
        Self { builtins: input.0 }
    }
}

/// Runs the Cairo program in proof mode with public and private inputs.
/// Mimics the behavior of the `run` function from cairo-vm-cli.
#[allow(clippy::too_many_arguments)]
pub fn run_proof_mode(
    entrypoint: String,
    program_inputs: PyObject,
    compiled_program_path: String,
    output_dir: PathBuf,
    stwo_proof: bool,
    proof_path: Option<PathBuf>,
    verify: bool,
) -> PyResult<()> {
    // Limit tracing to the current module
    let filter = EnvFilter::new("vm::vm::runner=info,warn");
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_span_events(FmtSpan::ENTER | FmtSpan::CLOSE)
        .with_env_filter(filter)
        .init();

    let cairo_run_config: CairoRunConfig<'_> = CairoRunConfig {
        entrypoint: &entrypoint,
        trace_enabled: true,
        relocate_mem: true,
        layout: LayoutName::all_cairo,
        proof_mode: true,
        secure_run: Some(true),
        allow_missing_builtins: Some(false),
        ..Default::default()
    };

    //this entrypoint tells which function to run in the cairo program
    let program_content = std::fs::read(compiled_program_path)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
    let program = Program::from_bytes(&program_content, Some(cairo_run_config.entrypoint))
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

    // Prepare execution scopes to allow running pythonic hints for args_gen
    let mut exec_scopes = ExecutionScopes::new();
    let dict_manager = DictManager::new();
    exec_scopes.insert_value("dict_manager", Rc::new(RefCell::new(dict_manager)));

    // Initialize a python context object that will be accessible throughout the execution of
    // all hints.
    // This enables us to directly use the Python identifiers passed in, avoiding the need to
    // serialize and deserialize the program JSON.
    Python::with_gil(|py| {
        let context = PyDict::new(py);

        context.set_item("program_inputs", program_inputs)?;

        let identifiers = program
            .iter_identifiers()
            .map(|(name, identifier)| (name.to_string(), identifier.clone()))
            .collect::<HashMap<String, Identifier>>();

        // Insert the _rust_ program_identifiers in the exec_scopes, so that we're able to
        // pull identifier data when executing hints to build VmConsts.
        exec_scopes.insert_value("__program_identifiers__", identifiers);

        // Store empty python identifiers directly in the context
        context
            .set_item("py_identifiers", PyDict::new(py))
            .map_err(|e: PyErr| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        // We don't need `serialize` to be available in the context - inject a None value.
        context.set_item("cairo_file", Option::<String>::None)?;

        // Import and run the initialization code from the injected module
        let setup_code = r#"
try:
    from cairo_addons.hints.injected import prepare_context
    prepare_context(lambda: globals())
except Exception as e:
    print(f"Warning: Error during initialization: {e}")
"#;

        // Run the initialization code
        py.run(&CString::new(setup_code)?, Some(&context), None).map_err(|e| {
            PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!(
                "Failed to initialize Python globals: {}",
                e
            ))
        })?;

        // Store the context object, modified in the initialization code, in the exec_scopes
        // to access it throughout the execution of hints
        let unbounded_context: Py<PyDict> = context.into_py_dict(py)?.into();
        exec_scopes.insert_value("__context__", unbounded_context);
        Ok::<(), PyErr>(())
    })?;

    let mut hint_processor = HintProcessor::default().with_dynamic_python_hints(false).build();

    let run_span = tracing::span!(tracing::Level::INFO, "cairo_run_program");
    let _run_span_guard = run_span.enter();
    let cairo_runner = match cairo_run::cairo_run_program_with_initial_scope(
        &program,
        &cairo_run_config,
        &mut hint_processor,
        exec_scopes,
    ) {
        Ok(runner) => runner,
        Err(error) => {
            tracing::error!("Failed to run program: {}", error);
            panic!("Failed to run block, exiting");
        }
    };
    drop(_run_span_guard);

    let execution_resources = cairo_runner.get_execution_resources().unwrap();
    tracing::info!("Execution resources: {:?}", execution_resources);

    if stwo_proof {
        // Create a performance tracing span for proof generation
        let proof_span = tracing::span!(tracing::Level::INFO, "stwo_proof_generation");
        let _proof_span_guard = proof_span.enter();

        // Convert CairoRunner to Stwo ProverInput
        let cairo_input = stwo_cairo_adapter::plain::adapt_finished_runner(cairo_runner)
            .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

        let prover_execution_resources = ProverExecutionResources::from_prover_input(&cairo_input);
        tracing::debug!("Prover Execution resources: {:#?}", prover_execution_resources);

        let ProverParameters { channel_hash: _, pcs_config, preprocessed_trace } =
            default_prod_prover_parameters();

        // Generate the proof
        let proof =
            prove_cairo::<Blake2sMerkleChannel>(cairo_input, pcs_config, preprocessed_trace)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
        drop(_proof_span_guard);
        tracing::info!("Proof generation completed");

        let proof_path = proof_path.unwrap_or_else(|| output_dir.join("proof.json"));
        std::fs::write(
            &proof_path,
            serde_json::to_string(&proof)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?,
        )?;
        tracing::info!("Proof written to {}", proof_path.display());

        // Optional verification
        if verify {
            let verify_span = tracing::span!(tracing::Level::INFO, "proof_verification");
            let _verify_span_guard = verify_span.enter();

            verify_cairo::<Blake2sMerkleChannel>(proof, pcs_config, preprocessed_trace)
                .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
            drop(_verify_span_guard);
            tracing::info!("Proof verified successfully");
        }
        return Ok(());
    }

    // Create a performance tracing span for output writing
    let output_span = tracing::span!(tracing::Level::INFO, "write_outputs");
    let _output_span_guard = output_span.enter();

    // Write execution outputs to files.
    let trace_path = output_dir.join("trace.bin");
    let memory_path = output_dir.join("memory.bin");
    let air_public_input = output_dir.join("air_public_input.json");
    let air_private_input = output_dir.join("air_private_input.json");

    let relocated_trace =
        cairo_runner
            .relocated_trace
            .as_ref()
            .ok_or(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>("Trace not relocated"))?;

    let trace_file = std::fs::File::create(&trace_path)?;
    let mut trace_writer =
        FileWriter::new(io::BufWriter::with_capacity(3 * 1024 * 1024, trace_file));

    cairo_run::write_encoded_trace(relocated_trace, &mut trace_writer)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
    trace_writer.flush()?;

    let memory_file = std::fs::File::create(&memory_path)?;
    let mut memory_writer =
        FileWriter::new(io::BufWriter::with_capacity(5 * 1024 * 1024, memory_file));
    write_encoded_memory(&cairo_runner.relocated_memory, &mut memory_writer)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
    memory_writer.flush()?;

    let json = cairo_runner
        .get_air_public_input()
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?
        .serialize_json()
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
    std::fs::write(&air_public_input, json)
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;

    let trace_path = trace_path.canonicalize().unwrap_or(trace_path).to_string_lossy().to_string();
    let memory_path =
        memory_path.canonicalize().unwrap_or(memory_path).to_string_lossy().to_string();
    let json = cairo_runner
        .get_air_private_input()
        .to_serializable(trace_path.clone(), memory_path.clone())
        .serialize_json()
        .map_err(|e| PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string()))?;
    std::fs::write(&air_private_input, json)?;

    Ok(())
}
