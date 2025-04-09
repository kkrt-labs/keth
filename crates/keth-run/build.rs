fn main() {
    if std::env::var("VIRTUAL_ENV").is_err() {
        println!("VIRTUAL_ENV not set, using default python");
    }
}
