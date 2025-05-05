use std::{io::Write, path::PathBuf};

use crate::vm::to_pyerr;
use cairo_air::{verifier::verify_cairo, CairoProof, PreProcessedTraceVariant};
use pyo3::{
    prelude::*,
    pyfunction, pymodule,
    types::{PyModule, PyModuleMethods},
    wrap_pyfunction, Bound, PyResult,
};
use stwo_cairo_adapter::{plain::prover_input_from_vm_output, ProverInput};
use stwo_cairo_prover::{
    prover::{default_prod_prover_parameters, prove_cairo, ProverParameters},
    stwo_prover::core::vcs::blake2_merkle::{Blake2sMerkleChannel, Blake2sMerkleHasher},
};
use stwo_cairo_serialize::CairoSerialize;
use stwo_cairo_utils::file_utils::create_file;
use tracing_subscriber::fmt::format::FmtSpan;

/// Python binding to generate a proof from prover inputs
#[pyfunction]
pub fn prove(prover_input_path: PathBuf, proof_path: PathBuf, serde_cairo: bool) -> PyResult<()> {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_span_events(FmtSpan::ENTER | FmtSpan::CLOSE)
        .try_init();
    let prover_input = prover_input_from_vm_output(&prover_input_path).map_err(to_pyerr)?;
    prove_with_stwo(prover_input, proof_path, serde_cairo, false).map_err(to_pyerr)
}

/// Python binding to verify a proof
#[pyfunction]
pub fn verify(proof_path: PathBuf) -> PyResult<()> {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_span_events(FmtSpan::ENTER | FmtSpan::CLOSE)
        .try_init();
    let proof_str = std::fs::read_to_string(&proof_path)?;
    let proof: CairoProof<Blake2sMerkleHasher> =
        sonic_rs::from_str(&proof_str).map_err(to_pyerr)?;
    let ProverParameters { channel_hash: _, pcs_config, preprocessed_trace } =
        default_prod_prover_parameters();
    verify_cairo::<Blake2sMerkleChannel>(proof, pcs_config, preprocessed_trace)
        .map_err(to_pyerr)?;
    Ok(())
}

/// Python module exposing STWO prover and verifier functions.
#[pymodule]
#[pyo3(submodule)]
pub fn stwo_bindings(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_function(wrap_pyfunction!(prove, module)?)?;
    module.add_function(wrap_pyfunction!(verify, module)?)?;
    init(module)
}

/// Workaround for https://github.com/PyO3/pyo3/issues/759
fn init(m: &Bound<'_, PyModule>) -> PyResult<()> {
    Python::with_gil(|py| {
        py.import("sys")?
            .getattr("modules")?
            .set_item("cairo_addons.rust_bindings.stwo_bindings", m)
    })
}

/// Proves a given prover input with STWO
///
/// Doesn't support proving pedersen hashes, because for performance purposes we prove with the
/// CanonicalWithoutPedersen variant preprocessed trace, which is faster to setup.
///
/// # Arguments
///
/// * `prover_input` - The prover input to prove
/// * `proof_path` - The path to save the proof
/// * `serde_cairo` - If false, the proof is serialized to a JSON format to be used by the Rust
///   Verifier. If true, the proof is serialized as an array of field elements serialized as hex
///   strings, compatible with `scarb execute`.
/// * `verify` - Whether to verify the proof as well
pub fn prove_with_stwo(
    prover_input: ProverInput,
    proof_path: PathBuf,
    serde_cairo: bool,
    verify: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let pcs_config = Default::default();
    let preprocessed_trace = PreProcessedTraceVariant::CanonicalWithoutPedersen;
    let proof = prove_cairo::<Blake2sMerkleChannel>(prover_input, pcs_config, preprocessed_trace)?;
    let mut proof_file = create_file(&proof_path)?;
    if serde_cairo {
        let mut serialized: Vec<starknet_ff::FieldElement> = Vec::new();
        CairoSerialize::serialize(&proof, &mut serialized);
        let hex_strings: Vec<String> =
            serialized.into_iter().map(|felt| format!("0x{:x}", felt)).collect();

        proof_file.write_all(sonic_rs::to_string_pretty(&hex_strings)?.as_bytes())?;
    } else {
        proof_file.write_all(sonic_rs::to_string_pretty(&proof)?.as_bytes())?;
    }
    if verify {
        verify_cairo::<Blake2sMerkleChannel>(proof, pcs_config, preprocessed_trace)?;
    }
    Ok(())
}
