use num_bigint::BigUint;
use pyo3::pyfunction;
use starknet_crypto::poseidon_hash_many as poseidon_hash_many_native;
use starknet_types_core::felt::Felt;

/// A binding to the `poseidon_hash_many` function from `starknet-crypto` which is considerably
/// faster that its Python equivalent.
#[pyfunction]
pub fn poseidon_hash_many(elements: Vec<BigUint>) -> BigUint {
    let elems_f252 = elements.iter().map(|e| Felt::from(e.clone())).collect::<Vec<_>>();
    let res = poseidon_hash_many_native(&elems_f252);
    res.to_biguint()
}
