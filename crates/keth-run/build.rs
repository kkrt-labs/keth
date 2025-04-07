fn main() {
    println!("cargo:rustc-env=PYTHONPATH=.venv/lib/python3.10/site-packages:python/eth-rpc/src:python/mpt/src:python/cairo-addons/src:python/cairo-core/src:python/cairo-ec/src:cairo");
    println!("cargo:rustc-env=PYO3_PYTHON=.venv/bin/python");
    // TODO: adapt this line to your python installation
    println!("cargo:rustc-env=PYTHONHOME=/Users/nabil/.local/share/uv/python/cpython-3.10.16-macos-aarch64-none");
}
