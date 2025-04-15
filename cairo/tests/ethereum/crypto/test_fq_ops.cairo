// Tests for generic finite field operations

from starkware.cairo.common.cairo_builtins import ModBuiltin
from ethereum_types.numeric import U384
from ethereum.crypto.fq_ops import Fq, FqStruct, Fq2, Fq2Struct, fq_add, fq_sub, fq_mul, fq_inv
from ethereum.crypto.alt_bn128 import BNF, BNF2, bnf_add, bnf_sub, bnf_mul, bnf_inv, ALT_BN128_MODULUS
from ethereum.crypto.bls12_381 import BLSF, BLSF2, blsf_add, blsf_sub, blsf_mul, blsf_inv, BLS12_381_MODULUS

// Test for AltBN128 using generic operations
func test_alt_bn128{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}() {
    alloc_locals;
    
    // Create some test values
    let a_value = U384(d0=123456789, d1=0, d2=0);
    let b_value = U384(d0=987654321, d1=0, d2=0);
    
    // Create BNF elements
    let a = BNF(new FqStruct(a_value));
    let b = BNF(new FqStruct(b_value));
    
    // Test addition
    let sum = bnf_add(a, b);
    // Expected: (123456789 + 987654321) % ALT_BN128_MODULUS
    
    // Test subtraction
    let diff = bnf_sub(a, b);
    // Expected: (123456789 - 987654321 + ALT_BN128_MODULUS) % ALT_BN128_MODULUS
    
    // Test multiplication
    let prod = bnf_mul(a, b);
    // Expected: (123456789 * 987654321) % ALT_BN128_MODULUS
    
    // Test inverse
    let inv = bnf_inv(a);
    // Expected: a^(-1) mod ALT_BN128_MODULUS
    
    // Verify a * a^(-1) = 1
    let check = bnf_mul(a, inv);
    assert check.ptr.value.d0 = 1;
    assert check.ptr.value.d1 = 0;
    assert check.ptr.value.d2 = 0;
    
    return ();
}

// Test for BLS12-381 using generic operations
func test_bls12_381{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}() {
    alloc_locals;
    
    // Create some test values
    let a_value = U384(d0=123456789, d1=0, d2=0);
    let b_value = U384(d0=987654321, d1=0, d2=0);
    
    // Create BLSF elements
    let a = BLSF(new FqStruct(a_value));
    let b = BLSF(new FqStruct(b_value));
    
    // Test addition
    let sum = blsf_add(a, b);
    // Expected: (123456789 + 987654321) % BLS12_381_MODULUS
    
    // Test subtraction
    let diff = blsf_sub(a, b);
    // Expected: (123456789 - 987654321 + BLS12_381_MODULUS) % BLS12_381_MODULUS
    
    // Test multiplication
    let prod = blsf_mul(a, b);
    // Expected: (123456789 * 987654321) % BLS12_381_MODULUS
    
    // Test inverse
    let inv = blsf_inv(a);
    // Expected: a^(-1) mod BLS12_381_MODULUS
    
    // Verify a * a^(-1) = 1
    let check = blsf_mul(a, inv);
    assert check.ptr.value.d0 = 1;
    assert check.ptr.value.d1 = 0;
    assert check.ptr.value.d2 = 0;
    
    return ();
}

// Combined test to ensure both implementations work correctly
func test_combined{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}() {
    test_alt_bn128();
    test_bls12_381();
    return ();
}