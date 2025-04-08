fn main() {
    println!("cargo:rerun-if-changed=build.rs");

    dotenvy::dotenv().expect("Failed to load .env file");

    dotenvy::var("PYTHONPATH").expect("PYTHONPATH environment variable not set");
    dotenvy::var("PYTHONHOME").expect("PYTHONHOME environment variable not set");

    println!("cargo:rerun-if-env-changed=PYTHONPATH");
    println!("cargo:rerun-if-env-changed=PYTHONHOME");
}
