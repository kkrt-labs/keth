fn main() {
    std::env::var("PYTHONPATH").expect("PYTHONPATH environment variable not set");
    std::env::var("PYTHONHOME").expect("PYTHONHOME environment variable not set");
    std::env::var("PYO3_PYTHON").expect("PYO3_PYTHON environment variable not set");
}
