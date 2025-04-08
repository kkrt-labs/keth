fn main() {
    std::env::var("VIRTUAL_ENV")
        .expect("VIRTUAL_ENV environment variable not set, activate your venv");
}
