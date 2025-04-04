use cairo_vm::{
    serde::deserialize_program::{Identifier, Member},
    types::relocatable::{MaybeRelocatable, Relocatable},
};
use std::collections::HashMap;

/// Represents the different types of Cairo variables that can be accessed in hints.
#[derive(Debug, Clone)]
pub enum CairoVarType {
    Felt,
    Relocatable,
    /// A composite type with named members.
    Struct {
        /// Fully qualified name of the struct type.
        name: String,
        /// Map of member names to their definitions (lazy-loaded).
        members: HashMap<String, Member>,
        /// Size of the struct in felts.
        size: usize,
    },
    /// A pointer to another type.
    Pointer {
        /// The type being pointed to.
        pointee: Box<CairoVarType>,
    },
}

/// Holds metadata about a Cairo variable for use in hints.
#[derive(Debug, Clone)]
pub struct CairoVar {
    /// Name of the variable as used in the hint.
    pub name: String,
    /// Current value of the variable, if available.
    pub value: Option<MaybeRelocatable>,
    /// Memory address of the variable, if assigned.
    pub address: Option<Relocatable>,
    /// Type information for the variable.
    pub var_type: CairoVarType,
}

/// Extracts struct member information from program identifiers.
///
/// # Arguments
/// - `identifiers`: Map of type names to their definitions.
/// - `type_name`: Name of the struct type to query.
///
/// # Returns
/// A tuple of `(members, size)` if successful, or `None` if the type is not found.
pub fn get_struct_info_from_identifiers(
    identifiers: &HashMap<String, Identifier>,
    type_name: &str,
) -> Option<(HashMap<String, Member>, usize)> {
    let base_type_name = type_name.trim_end_matches('*');
    let identifier = identifiers.get(base_type_name)?;
    let members_map = identifier.members.as_ref()?;

    let mut members = HashMap::new();
    for (member_name, member_def) in members_map {
        members.insert(member_name.clone(), member_def.clone());
    }

    let size = identifier.size.unwrap_or(1);
    Some((members, size))
}

/// Creates a `CairoVarType` from a type name and program identifiers.
///
/// # Arguments
/// - `type_name`: String representation of the type (e.g., "felt", "MyStruct", "felt*").
/// - `identifiers`: Program identifiers for resolving struct definitions.
///
/// # Returns
/// A `Result` containing the constructed type or an error if invalid.
pub fn create_var_type(
    type_name: &str,
    identifiers: &HashMap<String, Identifier>,
) -> Result<CairoVarType, String> {
    if type_name == "felt" {
        return Ok(CairoVarType::Felt);
    }

    if type_name.ends_with('*') {
        let base_type = type_name.trim_end_matches('*');
        let asterisks_count = type_name.len() - base_type.len();
        let mut inner_type = if base_type == "felt" {
            CairoVarType::Relocatable
        } else {
            match get_struct_info_from_identifiers(identifiers, base_type) {
                Some((members, size)) => {
                    CairoVarType::Struct { name: base_type.to_string(), members, size }
                }
                None => {
                    if base_type == "(fp_val: felt, pc_val: felt*)" {
                        // Manual handling of fp_val and pc_val, which causes issues in both VMs.
                        // return a dummy value instead.
                        return Ok(CairoVarType::Struct {
                            name: base_type.to_string(),
                            members: HashMap::new(),
                            size: 2,
                        });
                    }
                    return Err(format!("Could not get struct info for type '{}'", base_type));
                }
            }
        };

        // Add pointer layers
        for _ in 0..asterisks_count {
            inner_type = CairoVarType::Pointer { pointee: Box::new(inner_type) };
        }
        return Ok(inner_type);
    }

    Ok(CairoVarType::Struct { name: type_name.to_string(), members: HashMap::new(), size: 1 })
}
