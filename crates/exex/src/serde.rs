use cairo_vm::{
    serde::deserialize_program::Identifier,
    types::{
        errors::math_errors::MathError,
        relocatable::{MaybeRelocatable, Relocatable},
    },
    vm::{errors::memory_errors::MemoryError, runners::cairo_runner::CairoRunner},
    Felt252,
};
use std::collections::HashMap;
use thiserror::Error;

/// Represents errors that can occur during the serialization and deserialization processes between
/// Cairo VM programs and Rust representations.
#[derive(Debug, Error)]
pub enum KakarotSerdeError {
    /// Error variant indicating that no identifier matching the specified name was found.
    #[error("Expected one struct named '{struct_name}', found 0 matches. Expected type: {expected_type:?}")]
    IdentifierNotFound {
        /// The name of the struct that was not found.
        struct_name: String,
        /// The expected type of the struct (if applicable).
        expected_type: Option<String>,
    },

    /// Error variant indicating that multiple identifiers matching the specified name were found.
    #[error("Expected one struct named '{struct_name}', found {count} matches. Expected type: {expected_type:?}")]
    MultipleIdentifiersFound {
        /// The name of the struct for which multiple identifiers were found.
        struct_name: String,
        /// The expected type of the struct (if applicable).
        expected_type: Option<String>,
        /// The number of matching identifiers found.
        count: usize,
    },

    /// Error variant indicating a Math error in CairoVM operations
    #[error(transparent)]
    CairoVmMath(#[from] MathError),

    /// Error variant indicating a memory error in CairoVM operations
    #[error(transparent)]
    CairoVmMemory(#[from] MemoryError),
}

/// A structure representing the Kakarot serialization and deserialization context for Cairo
/// programs.
///
/// This struct encapsulates the components required to serialize and deserialize
/// Kakarot programs, including:
/// - The Cairo runner responsible for executing the program
#[allow(missing_debug_implementations)]
pub struct KakarotSerde {
    /// The Cairo runner used to execute Kakarot programs.
    ///
    /// This runner interacts with the Cairo virtual machine, providing the necessary
    /// infrastructure for running and managing the execution of Cairo programs.
    /// It is responsible for handling program execution flow, managing state, and
    /// providing access to program identifiers.
    runner: CairoRunner,
}

impl KakarotSerde {
    /// Retrieves a unique identifier from the Cairo program based on the specified struct name and
    /// expected type.
    ///
    /// This function searches for identifiers that match the provided struct name and type within
    /// the Cairo program's identifier mappings. It returns an error if no identifiers or
    /// multiple identifiers are found.
    pub fn get_identifier(
        &self,
        struct_name: &str,
        expected_type: Option<String>,
    ) -> Result<Identifier, KakarotSerdeError> {
        // Retrieve identifiers from the program and filter them based on the struct name and
        // expected type
        let identifiers = self
            .runner
            .get_program()
            .iter_identifiers()
            .filter(|(key, value)| {
                key.contains(struct_name) &&
                    key.split('.').last() == struct_name.split('.').last() &&
                    value.type_ == expected_type
            })
            .map(|(_, value)| value)
            .collect::<Vec<_>>();

        // Match on the number of found identifiers
        match identifiers.len() {
            // No identifiers found
            0 => Err(KakarotSerdeError::IdentifierNotFound {
                struct_name: struct_name.to_string(),
                expected_type,
            }),
            // Exactly one identifier found, return it
            1 => Ok(identifiers[0].clone()),
            // More than one identifier found
            count => Err(KakarotSerdeError::MultipleIdentifiersFound {
                struct_name: struct_name.to_string(),
                expected_type,
                count,
            }),
        }
    }

    /// Serializes a pointer to a Hashmap by resolving its members from memory.
    ///
    /// We provide:
    /// - The name of the struct whose pointer is being serialized.
    /// - The memory location (pointer) of the struct.
    ///
    /// We expect:
    /// - A map of member names to their corresponding values (or `None` if the pointer is 0).
    pub fn serialize_pointers(
        &self,
        struct_name: &str,
        ptr: Relocatable,
    ) -> Result<HashMap<String, Option<MaybeRelocatable>>, KakarotSerdeError> {
        // Fetch the struct definition (identifier) by name.
        let identifier = self.get_identifier(struct_name, Some("struct".to_string()))?;

        // Initialize the output map.
        let mut output = HashMap::new();

        // If the struct has members, iterate over them to resolve their values from memory.
        if let Some(members) = identifier.members {
            for (name, member) in members {
                // We try to resolve the member's value from memory.
                if let Some(member_ptr) = self.runner.vm.get_maybe(&(ptr + member.offset)?) {
                    // Check for null pointer.
                    if member_ptr == MaybeRelocatable::Int(Felt252::ZERO) &&
                        member.cairo_type.ends_with('*')
                    {
                        // We insert `None` for cases such as `parent=cast(0, model.Parent*)`
                        //
                        // Null pointers are represented as `None`.
                        output.insert(name, None);
                    } else {
                        // Insert the resolved member pointer into the output map.
                        output.insert(name, Some(member_ptr));
                    }
                }
            }
        }

        Ok(output)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use cairo_vm::types::{layout_name::LayoutName, program::Program};

    fn setup_kakarot_serde() -> KakarotSerde {
        // Load the valid program content from a JSON file
        let program_content = include_bytes!("../testdata/keccak_add_uint256.json");

        // Create a Program instance from the loaded bytes, specifying "main" as the entry point
        let program = Program::from_bytes(program_content, Some("main")).unwrap();

        // Initialize a CairoRunner with the created program and default parameters
        let runner = CairoRunner::new(&program, LayoutName::plain, false, false).unwrap();

        // Return an instance of KakarotSerde
        KakarotSerde { runner }
    }

    #[test]
    fn test_program_identifier_valid() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde();

        // Check if the identifier "main" with expected type "function" is correctly retrieved
        assert_eq!(
            kakarot_serde.get_identifier("main", Some("function".to_string())).unwrap(),
            Identifier {
                pc: Some(96),
                type_: Some("function".to_string()),
                value: None,
                full_name: None,
                members: None,
                cairo_type: None
            }
        );

        // Check if the identifier "__temp0" with expected type "reference" is correctly retrieved
        assert_eq!(
            kakarot_serde.get_identifier("__temp0", Some("reference".to_string())).unwrap(),
            Identifier {
                pc: None,
                type_: Some("reference".to_string()),
                value: None,
                full_name: Some(
                    "starkware.cairo.common.uint256.word_reverse_endian.__temp0".to_string()
                ),
                members: None,
                cairo_type: Some("felt".to_string())
            }
        );
    }

    #[test]
    fn test_non_existent_identifier() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde();

        // Test for a non-existent identifier
        let result =
            kakarot_serde.get_identifier("non_existent_struct", Some("function".to_string()));

        // Check if the error is valid and validate its parameters
        if let Err(KakarotSerdeError::IdentifierNotFound { struct_name, expected_type }) = result {
            assert_eq!(struct_name, "non_existent_struct");
            assert_eq!(expected_type, Some("function".to_string()));
        } else {
            panic!("Expected KakarotSerdeError::IdentifierNotFound");
        }
    }

    #[test]
    fn test_incorrect_identifier_usage() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde();

        // Test for an identifier used incorrectly (not the last segment of the full name)
        let result = kakarot_serde.get_identifier("check_range", Some("struct".to_string()));

        // Check if the error is valid and validate its parameters
        if let Err(KakarotSerdeError::IdentifierNotFound { struct_name, expected_type }) = result {
            assert_eq!(struct_name, "check_range");
            assert_eq!(expected_type, Some("struct".to_string()));
        } else {
            panic!("Expected KakarotSerdeError::IdentifierNotFound");
        }
    }

    #[test]
    fn test_valid_identifier_incorrect_type() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde();

        // Test for a valid identifier but with an incorrect type
        let result = kakarot_serde.get_identifier("main", Some("struct".to_string()));

        // Check if the error is valid and validate its parameters
        if let Err(KakarotSerdeError::IdentifierNotFound { struct_name, expected_type }) = result {
            assert_eq!(struct_name, "main");
            assert_eq!(expected_type, Some("struct".to_string()));
        } else {
            panic!("Expected KakarotSerdeError::IdentifierNotFound");
        }
    }

    #[test]
    fn test_identifier_with_multiple_matches() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde();

        // Test for an identifier with multiple matches
        let result = kakarot_serde.get_identifier("ImplicitArgs", Some("struct".to_string()));

        // Check if the error is valid and validate its parameters
        if let Err(KakarotSerdeError::MultipleIdentifiersFound {
            struct_name,
            expected_type,
            count,
        }) = result
        {
            assert_eq!(struct_name, "ImplicitArgs");
            assert_eq!(expected_type, Some("struct".to_string()));
            assert_eq!(count, 6);
        } else {
            panic!("Expected KakarotSerdeError::MultipleIdentifiersFound");
        }
    }

    #[test]
    fn test_serialize_pointer_not_struct() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde();

        // Add a new memory segment to the virtual machine (VM).
        let base = kakarot_serde.runner.vm.add_memory_segment();

        // Attempt to serialize pointer with "main", expecting an IdentifierNotFound error.
        let result = kakarot_serde.serialize_pointers("main", base);

        // Assert that the result is an error with the expected struct name and type.
        match result {
            Err(KakarotSerdeError::IdentifierNotFound { struct_name, expected_type }) => {
                assert_eq!(struct_name, "main".to_string());
                assert_eq!(expected_type, Some("struct".to_string()));
            }
            _ => panic!("Expected KakarotSerdeError::IdentifierNotFound, but got: {:?}", result),
        }
    }

    #[test]
    fn test_serialize_pointer_empty() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde();

        // Serialize the pointers of the "ImplicitArgs" struct but without any memory segment.
        let result = kakarot_serde
            .serialize_pointers("main.ImplicitArgs", Relocatable::default())
            .expect("failed to serialize pointers");

        // The result should be an empty HashMap since there is no memory segment.
        assert!(result.is_empty(),);
    }

    #[test]
    fn test_serialize_pointer_valid() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde();

        // Setup
        let output_ptr = Felt252::ZERO;
        let range_check_ptr = kakarot_serde.runner.vm.add_memory_segment();
        let bitwise_ptr = kakarot_serde.runner.vm.add_memory_segment();

        // Insert relocatable values in memory
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                MaybeRelocatable::Int(output_ptr),
                MaybeRelocatable::RelocatableValue(range_check_ptr),
                MaybeRelocatable::RelocatableValue(bitwise_ptr),
            ])
            .unwrap()
            .get_relocatable()
            .unwrap();

        // Serialize the pointers of the "ImplicitArgs" struct using the new memory segment.
        let result = kakarot_serde
            .serialize_pointers("main.ImplicitArgs", base)
            .expect("failed to serialize pointers");

        // Assert that the result matches the expected serialized struct members.
        assert_eq!(
            result,
            HashMap::from_iter([
                ("output_ptr".to_string(), None),
                (
                    "range_check_ptr".to_string(),
                    Some(MaybeRelocatable::RelocatableValue(range_check_ptr))
                ),
                ("bitwise_ptr".to_string(), Some(MaybeRelocatable::RelocatableValue(bitwise_otr))),
            ])
        );
    }

    #[test]
    fn test_serialize_null_no_pointer() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde();

        // Setup
        let output_ptr = Relocatable { segment_index: 10, offset: 11 };
        let range_check_ptr = Felt252::ZERO;
        let bitwise_ptr = Felt252::from(55);

        // Insert relocatable values in memory
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                MaybeRelocatable::RelocatableValue(output_ptr),
                MaybeRelocatable::Int(range_check_ptr),
                MaybeRelocatable::Int(bitwise_ptr),
            ])
            .unwrap()
            .get_relocatable()
            .unwrap();

        // Serialize the pointers of the "ImplicitArgs" struct using the new memory segment.
        let result = kakarot_serde
            .serialize_pointers("main.ImplicitArgs", base)
            .expect("failed to serialize pointers");

        // Assert that the result matches the expected serialized struct members.
        assert_eq!(
            result,
            HashMap::from_iter([
                ("output_ptr".to_string(), Some(MaybeRelocatable::RelocatableValue(output_ptr))),
                // Not a pointer so that we shouldn't have a `None`
                ("range_check_ptr".to_string(), Some(MaybeRelocatable::Int(range_check_ptr))),
                ("bitwise_ptr".to_string(), Some(MaybeRelocatable::Int(bitwise_otr))),
            ])
        );
    }
}
