use blake2::{Blake2s256, Digest};
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

// TODO verify whether it's actually faster...
/// A binding to the `blake2s_hash_many` function from `blake2` which is considerably
/// faster that its Python equivalent.
/// The resulting hash is truncated to 251 bits.
#[pyfunction]
pub fn blake2s_hash_many(elements: Vec<BigUint>) -> BigUint {
    let mut hasher = Blake2s256::new();
    for elem in elements {
        let elem_bytes = elem.to_bytes_le();
        let mut elem_bytes32 = [0u8; 32];
        elem_bytes32[..elem_bytes.len()].copy_from_slice(&elem_bytes);
        hasher.update(elem_bytes32);
    }
    let hash = hasher.finalize();
    BigUint::from_bytes_le(&hash[..31])
}
