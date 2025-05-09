use std::env;

use pyo3::{
    prelude::*,
    pymodule,
    types::{PyModule, PyModuleMethods},
    wrap_pymodule, Bound,
};
use tracing_subscriber::{
    fmt, fmt::format::FmtSpan, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter,
};

mod stwo_bindings;
mod vm;

fn setup_logging() -> Result<(), Box<dyn std::error::Error>> {
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info"));

    let log_format = env::var("LOG_FORMAT").unwrap_or_else(|_| "plain".to_string());

    match log_format.as_str() {
        "json" => {
            // JSON structured logging without ANSI colors
            let json_layer = fmt::layer()
                .json()
                .with_ansi(false) // Disable colors
                .with_span_events(FmtSpan::ENTER | FmtSpan::CLOSE);

            let _ = tracing_subscriber::registry().with(json_layer).with(env_filter).try_init();
        }
        _ => {
            // Plain text logging with ANSI colors (default)
            let fmt_layer = fmt::layer()
                .with_ansi(true) // Keep colors for plain text
                .with_span_events(FmtSpan::ENTER | FmtSpan::CLOSE);

            let _ = tracing_subscriber::registry().with(fmt_layer).with(env_filter).try_init();
        }
    }

    Ok(())
}

#[pymodule]
#[pyo3(name = "rust_bindings")]
fn rust_bindings(root_module: &Bound<'_, PyModule>) -> PyResult<()> {
    root_module.add_wrapped(wrap_pymodule!(stwo_bindings::stwo_bindings))?;
    root_module.add_wrapped(wrap_pymodule!(vm::vm))?;
    Ok(())
}
