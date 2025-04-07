#[cfg(not(test))]
fn main() {
    dotenv::dotenv().ok();

    dotenv::var("PYTHONPATH").expect("PYTHONPATH environment variable not set");
    dotenv::var("PYTHONHOME").expect("PYTHONHOME environment variable not set");
    dotenv::var("PYO3_PYTHON").expect("PYO3_PYTHON environment variable not set");

    println!("cargo:rerun-if-env-changed=PYTHONPATH");
    println!("cargo:rerun-if-env-changed=PYTHONHOME");
    println!("cargo:rerun-if-env-changed=PYO3_PYTHON");
}

// Empty stub to allow build to succeed when running `cargo test --all-features`
#[cfg(test)]
fn main() {}
