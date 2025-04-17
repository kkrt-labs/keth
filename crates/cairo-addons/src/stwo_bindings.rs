use std::path::PathBuf;

use crate::vm::to_pyerr;
use cairo_air::{verifier::verify_cairo, CairoProof};
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
use tracing_subscriber::fmt::format::FmtSpan;

/// Python binding to generate a proof from prover inputs
#[pyfunction]
pub fn prove(prover_input_path: PathBuf, proof_path: PathBuf) -> PyResult<()> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_span_events(FmtSpan::ENTER | FmtSpan::CLOSE)
        .init();
    let prover_input = prover_input_from_vm_output(&prover_input_path).map_err(to_pyerr)?;
    prove_with_stwo(prover_input, Some(proof_path), false).map_err(to_pyerr)
}

/// Python binding to verify a proof
#[pyfunction]
pub fn verify(proof_path: PathBuf) -> PyResult<()> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .with_span_events(FmtSpan::ENTER | FmtSpan::CLOSE)
        .init();
    let proof_str = std::fs::read_to_string(&proof_path)?;
    let proof: CairoProof<Blake2sMerkleHasher> =
        serde_json::from_str(&proof_str).map_err(to_pyerr)?;
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
/// # Arguments
///
/// * `prover_input` - The prover input to prove
/// * `proof_path` - The path to save the proof
/// * `verify` - Whether to verify the proof as well
pub fn prove_with_stwo(
    prover_input: ProverInput,
    proof_path: Option<PathBuf>,
    verify: bool,
) -> Result<(), Box<dyn std::error::Error>> {
    let ProverParameters { channel_hash: _, pcs_config, preprocessed_trace } =
        default_prod_prover_parameters();
    let proof = prove_cairo::<Blake2sMerkleChannel>(prover_input, pcs_config, preprocessed_trace)?;
    if let Some(proof_path) = proof_path {
        std::fs::write(proof_path, serde_json::to_string(&proof)?)?;
    }
    if verify {
        verify_cairo::<Blake2sMerkleChannel>(proof, pcs_config, preprocessed_trace)?;
    }
    Ok(())
}
