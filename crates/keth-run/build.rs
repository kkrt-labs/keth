fn main() {
    println!("cargo:rustc-env=PYTHONPATH=.venv/lib/python3.10/site-packages:python/eth-rpc/src:python/mpt/src:python/cairo-addons/src:python/cairo-core/src:python/cairo-ec/src:cairo");
    println!("cargo:rustc-env=PYO3_PYTHON=.venv/bin/python");
    // Get UV_ROOT from environment variable, with a fallback path
    let uv_root = std::env::var("UV_ROOT").unwrap_or_else(|_| {
        let home = std::env::var("HOME").expect("HOME environment variable not set");
        format!("{}/.local/share/uv", home)
    });
    println!("cargo:rustc-env=PYTHONHOME={}/python/cpython-3.10.16-macos-aarch64-none", uv_root);
}
