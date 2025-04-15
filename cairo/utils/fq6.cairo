// --- Fq6 Operations ---
func fq6_add{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: Fq6, b: Fq6, modulus: U384
) -> Fq6 {
    // Add two Fq6 elements component-wise
    alloc_locals;
    
    // Create Fq2 elements for component-wise operations
    let a_c0 = Fq2(new Fq2Struct(a.ptr.c0.c0, a.ptr.c0.c1));
    let a_c1 = Fq2(new Fq2Struct(a.ptr.c1.c0, a.ptr.c1.c1));
    let a_c2 = Fq2(new Fq2Struct(a.ptr.c2.c0, a.ptr.c2.c1));
    
    let b_c0 = Fq2(new Fq2Struct(b.ptr.c0.c0, b.ptr.c0.c1));
    let b_c1 = Fq2(new Fq2Struct(b.ptr.c1.c0, b.ptr.c1.c1));
    let b_c2 = Fq2(new Fq2Struct(b.ptr.c2.c0, b.ptr.c2.c1));
    
    // Add components
    let res_c0 = fq2_add(a_c0, b_c0, modulus);
    let res_c1 = fq2_add(a_c1, b_c1, modulus);
    let res_c2 = fq2_add(a_c2, b_c2, modulus);
    
    // Create new Fq6Struct with the results
    let result = new Fq6Struct(
        Fq2Struct(res_c0.ptr.c0, res_c0.ptr.c1),
        Fq2Struct(res_c1.ptr.c0, res_c1.ptr.c1),
        Fq2Struct(res_c2.ptr.c0, res_c2.ptr.c1)
    );
    
    return Fq6(result);
}

func fq6_sub{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: Fq6, b: Fq6, modulus: U384
) -> Fq6 {
    // Subtract two Fq6 elements component-wise
    alloc_locals;
    
    // Create Fq2 elements for component-wise operations
    let a_c0 = Fq2(new Fq2Struct(a.ptr.c0.c0, a.ptr.c0.c1));
    let a_c1 = Fq2(new Fq2Struct(a.ptr.c1.c0, a.ptr.c1.c1));
    let a_c2 = Fq2(new Fq2Struct(a.ptr.c2.c0, a.ptr.c2.c1));
    
    let b_c0 = Fq2(new Fq2Struct(b.ptr.c0.c0, b.ptr.c0.c1));
    let b_c1 = Fq2(new Fq2Struct(b.ptr.c1.c0, b.ptr.c1.c1));
    let b_c2 = Fq2(new Fq2Struct(b.ptr.c2.c0, b.ptr.c2.c1));
    
    // Subtract components
    let res_c0 = fq2_sub(a_c0, b_c0, modulus);
    let res_c1 = fq2_sub(a_c1, b_c1, modulus);
    let res_c2 = fq2_sub(a_c2, b_c2, modulus);
    
    // Create new Fq6Struct with the results
    let result = new Fq6Struct(
        Fq2Struct(res_c0.ptr.c0, res_c0.ptr.c1),
        Fq2Struct(res_c1.ptr.c0, res_c1.ptr.c1),
        Fq2Struct(res_c2.ptr.c0, res_c2.ptr.c1)
    );
    
    return Fq6(result);
}

func fq6_mul{range_check96_ptr: felt*, add_mod_ptr: ModBuiltin*, mul_mod_ptr: ModBuiltin*}(
    a: Fq6, b: Fq6, modulus: U384, non_residue: Fq2
) -> Fq6 {
    // Multiply two Fq6 elements
    // Representing Fq6 as Fq2[3] with a cubic non-residue
    alloc_locals;
    
    // Create Fq2 elements for component-wise operations
    let a_c0 = Fq2(new Fq2Struct(a.ptr.c0.c0, a.ptr.c0.c1));
    let a_c1 = Fq2(new Fq2Struct(a.ptr.c1.c0, a.ptr.c1.c1));
    let a_c2 = Fq2(new Fq2Struct(a.ptr.c2.c0, a.ptr.c2.c1));
    
    let b_c0 = Fq2(new Fq2Struct(b.ptr.c0.c0, b.ptr.c0.c1));
    let b_c1 = Fq2(new Fq2Struct(b.ptr.c1.c0, b.ptr.c1.c1));
    let b_c2 = Fq2(new Fq2Struct(b.ptr.c2.c0, b.ptr.c2.c1));
    
    // Karatsuba multiplication
    let v0 = fq2_mul(a_c0, b_c0, modulus);
    let v1 = fq2_mul(a_c1, b_c1, modulus);
    let v2 = fq2_mul(a_c2, b_c2, modulus);
    
    // Calculate intermediate terms
    let a0_plus_a1 = fq2_add(a_c0, a_c1, modulus);
    let b0_plus_b1 = fq2_add(b_c0, b_c1, modulus);
    let a1_plus_a2 = fq2_add(a_c1, a_c2, modulus);
    let b1_plus_b2 = fq2_add(b_c1, b_c2, modulus);
    let a0_plus_a2 = fq2_add(a_c0, a_c2, modulus);
    let b0_plus_b2 = fq2_add(b_c0, b_c2, modulus);
    
    let a0_plus_a1_mul_b0_plus_b1 = fq2_mul(a0_plus_a1, b0_plus_b1, modulus);
    let a1_plus_a2_mul_b1_plus_b2 = fq2_mul(a1_plus_a2, b1_plus_b2, modulus);
    let a0_plus_a2_mul_b0_plus_b2 = fq2_mul(a0_plus_a2, b0_plus_b2, modulus);
    
    // Calculate final components
    let term1 = fq2_add(v0, v1, modulus);
    let c0_temp = fq2_sub(a0_plus_a1_mul_b0_plus_b1, term1, modulus);
    
    let term2 = fq2_add(v1, v2, modulus);
    let c2_temp = fq2_sub(a1_plus_a2_mul_b1_plus_b2, term2, modulus);
    
    let term3 = fq2_add(v0, v2, modulus);
    let c1_temp = fq2_sub(a0_plus_a2_mul_b0_plus_b2, term3, modulus);
    
    // Adjust for the non-residue
    let v2_mul_non_residue = fq2_mul(v2, non_residue, modulus);
    let c0 = fq2_add(v0, v2_mul_non_residue, modulus);
    
    let v1_mul_non_residue = fq2_mul(v1, non_residue, modulus);
    let c1 = fq2_add(c1_temp, v1_mul_non_residue, modulus);
    
    let c2 = fq2_add(c2_temp, v0, modulus);
    
    // Create new Fq6Struct with the results
    let result = new Fq6Struct(
        Fq2Struct(c0.ptr.c0, c0.ptr.c1),
        Fq2Struct(c1.ptr.c0, c1.ptr.c1),
        Fq2Struct(c2.ptr.c0, c2.ptr.c1)
    );
    
    return Fq6(result);
}