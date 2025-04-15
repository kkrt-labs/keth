// Generic finite field operations for elliptic curves
// Shared between alt_bn128.cairo and bls12_381.cairo

from starkware.cairo.common.cairo_builtins import ModBuiltin
from ethereum_types.numeric import U384

// --- Base field structures ---
struct FqStruct {
    value: U384,
}

struct Fq {
    ptr: FqStruct*,
}

// --- Quadratic extension field structures ---
struct Fq2Struct {
    c0: U384,
    c1: U384,
}

struct Fq2 {
    ptr: Fq2Struct*,
}

// --- Sextic extension field structures (for Fq12) ---
struct Fq6Struct {
    c0: Fq2Struct,
    c1: Fq2Struct,
    c2: Fq2Struct,
}

struct Fq6 {
    ptr: Fq6Struct*,
}

// --- Dodecic extension field structures ---
struct Fq12Struct {
    c0: Fq6Struct,
    c1: Fq6Struct,
}

struct Fq12 {
    ptr: Fq12Struct*,
}

// --- Basic Fq Operations ---
func fq_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: Fq, b: Fq, modulus: U384
) -> Fq {
    // Add two field elements and reduce modulo 'modulus'
    alloc_locals;
    let a_val = a.ptr.value;
    let b_val = b.ptr.value;
    
    // Use add_mod to perform modular addition
    let result_ptr = add_mod_ptr;
    let res_value = add_mod(a_val, b_val, modulus);
    
    // Create new FqStruct with the result
    let result = new FqStruct(res_value);
    return Fq(result);
}

func fq_sub{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: Fq, b: Fq, modulus: U384
) -> Fq {
    // Subtract b from a and reduce modulo 'modulus'
    alloc_locals;
    let a_val = a.ptr.value;
    let b_val = b.ptr.value;
    
    // Check if b > a, if so, add modulus to a before subtracting
    let (is_b_gt_a) = is_le(a_val, b_val);
    let a_val_adjusted = a_val;
    if (is_b_gt_a != 0) {
        a_val_adjusted = add_mod(a_val, modulus, modulus);
    }
    
    // Perform subtraction
    let res_value = sub_mod(a_val_adjusted, b_val, modulus);
    
    // Create new FqStruct with the result
    let result = new FqStruct(res_value);
    return Fq(result);
}

func fq_mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: Fq, b: Fq, modulus: U384
) -> Fq {
    // Multiply two field elements and reduce modulo 'modulus'
    alloc_locals;
    let a_val = a.ptr.value;
    let b_val = b.ptr.value;
    
    // Use mul_mod to perform modular multiplication
    let res_value = mul_mod(a_val, b_val, modulus);
    
    // Create new FqStruct with the result
    let result = new FqStruct(res_value);
    return Fq(result);
}

func fq_inv{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: Fq, modulus: U384
) -> Fq {
    // Calculate multiplicative inverse of a in the field
    alloc_locals;
    let a_val = a.ptr.value;
    
    // This will be implemented using a hint
    let res_value: U384;
    %{
        from ethereum_types.numeric import U384
        
        # Get a as a Python integer
        a_int = ids.a_val.export()
        p_int = ids.modulus.export()
        
        # Compute modular inverse using pow in Python
        # a^(p-2) mod p = a^(-1) mod p by Fermat's Little Theorem
        if a_int == 0:
            result = 0
        else:
            result = pow(a_int, p_int - 2, p_int)
        
        # Import result back
        ids.res_value = U384(result)
    %}
    
    // Verify the result: a * a^(-1) should be 1 modulo p
    let product = mul_mod(a_val, res_value, modulus);
    let one = U384(d0=1, d1=0, d2=0);
    assert product = one;
    
    // Create new FqStruct with the result
    let result = new FqStruct(res_value);
    return Fq(result);
}

// --- Fq2 Operations ---
func fq2_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: Fq2, b: Fq2, modulus: U384
) -> Fq2 {
    // Add two Fq2 elements: (a.c0 + a.c1*i) + (b.c0 + b.c1*i) = (a.c0 + b.c0) + (a.c1 + b.c1)*i
    alloc_locals;
    
    // Create Fq elements for component-wise operations
    let a_c0 = Fq(new FqStruct(a.ptr.c0));
    let a_c1 = Fq(new FqStruct(a.ptr.c1));
    let b_c0 = Fq(new FqStruct(b.ptr.c0));
    let b_c1 = Fq(new FqStruct(b.ptr.c1));
    
    // Add components
    let res_c0 = fq_add(a_c0, b_c0, modulus);
    let res_c1 = fq_add(a_c1, b_c1, modulus);
    
    // Create new Fq2Struct with the results
    let result = new Fq2Struct(res_c0.ptr.value, res_c1.ptr.value);
    return Fq2(result);
}

func fq2_sub{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: Fq2, b: Fq2, modulus: U384
) -> Fq2 {
    // Subtract two Fq2 elements: (a.c0 + a.c1*i) - (b.c0 + b.c1*i) = (a.c0 - b.c0) + (a.c1 - b.c1)*i
    alloc_locals;
    
    // Create Fq elements for component-wise operations
    let a_c0 = Fq(new FqStruct(a.ptr.c0));
    let a_c1 = Fq(new FqStruct(a.ptr.c1));
    let b_c0 = Fq(new FqStruct(b.ptr.c0));
    let b_c1 = Fq(new FqStruct(b.ptr.c1));
    
    // Subtract components
    let res_c0 = fq_sub(a_c0, b_c0, modulus);
    let res_c1 = fq_sub(a_c1, b_c1, modulus);
    
    // Create new Fq2Struct with the results
    let result = new Fq2Struct(res_c0.ptr.value, res_c1.ptr.value);
    return Fq2(result);
}

func fq2_mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: Fq2, b: Fq2, modulus: U384
) -> Fq2 {
    // Multiply two Fq2 elements:
    // (a.c0 + a.c1*i) * (b.c0 + b.c1*i) = (a.c0*b.c0 - a.c1*b.c1) + (a.c0*b.c1 + a.c1*b.c0)*i
    alloc_locals;
    
    // Create Fq elements for component-wise operations
    let a_c0 = Fq(new FqStruct(a.ptr.c0));
    let a_c1 = Fq(new FqStruct(a.ptr.c1));
    let b_c0 = Fq(new FqStruct(b.ptr.c0));
    let b_c1 = Fq(new FqStruct(b.ptr.c1));
    
    // Calculate terms
    let a0b0 = fq_mul(a_c0, b_c0, modulus);
    let a1b1 = fq_mul(a_c1, b_c1, modulus);
    let a0b1 = fq_mul(a_c0, b_c1, modulus);
    let a1b0 = fq_mul(a_c1, b_c0, modulus);
    
    // Real part: a0*b0 - a1*b1
    let neg_a1b1 = fq_sub(Fq(new FqStruct(U384(d0=0, d1=0, d2=0))), a1b1, modulus);
    let res_c0 = fq_add(a0b0, neg_a1b1, modulus);
    
    // Imaginary part: a0*b1 + a1*b0
    let res_c1 = fq_add(a0b1, a1b0, modulus);
    
    // Create new Fq2Struct with the results
    let result = new Fq2Struct(res_c0.ptr.value, res_c1.ptr.value);
    return Fq2(result);
}

// Add other operations as needed: fq2_inv, fq6 operations, fq12 operations, etc.