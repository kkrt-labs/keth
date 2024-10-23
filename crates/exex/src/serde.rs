use cairo_vm::{
    serde::deserialize_program::Identifier,
    types::{errors::math_errors::MathError, relocatable::Relocatable},
    vm::{errors::memory_errors::MemoryError, runners::cairo_runner::CairoRunner},
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
    /// - A map of member names to their corresponding values (or `None` if the pointer is null).
    pub fn serialize_pointers(
        &self,
        struct_name: &str,
        ptr: Relocatable,
    ) -> Result<HashMap<String, Option<Relocatable>>, KakarotSerdeError> {
        // Fetch the struct definition (identifier) by name.
        let identifier = self.get_identifier(struct_name, Some("struct".to_string()))?;

        // Initialize the output map.
        let mut output = HashMap::new();

        // If the struct has members, iterate over them to resolve their values from memory.
        if let Some(members) = identifier.members {
            for (name, member) in members {
                // Get the member's pointer in memory by adding its offset to the struct pointer.
                let mut member_ptr = Some(self.runner.vm.get_relocatable((ptr + member.offset)?)?);

                // If the member is a pointer and its value is 0, set it to `None`.
                if member_ptr == Some(Relocatable::default()) && member.cairo_type.ends_with('*') {
                    member_ptr = None;
                }

                // Insert the resolved member pointer into the output map.
                output.insert(name, member_ptr);
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
        let program_content = include_bytes!("../testdata/os_program.json");

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
                pc: Some(3478),
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
                full_name: Some("starkware.cairo.common.memcpy.memcpy.__temp0".to_string()),
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
            assert_eq!(count, 63);
        } else {
            panic!("Expected KakarotSerdeError::MultipleIdentifiersFound");
        }
    }

    #[test]
    fn test_serialize_pointer_not_struct() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde();

        // Add a new memory segment to the virtual machine (VM).
        let _ = kakarot_serde.runner.vm.add_memory_segment();

        // Attempt to serialize pointer with "main", expecting an IdentifierNotFound error.
        let result =
            kakarot_serde.serialize_pointers("main", Relocatable { segment_index: 0, offset: 0 });

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
    fn test_serialize_pointer_valid() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde();

        // Insert relocatable values in memory
        let _ = kakarot_serde.runner.vm.gen_arg(&vec![
            Relocatable { segment_index: 0, offset: 0 },
            Relocatable { segment_index: 10, offset: 11 },
            Relocatable { segment_index: 10, offset: 11 },
            Relocatable { segment_index: 10, offset: 11 },
            Relocatable { segment_index: 10, offset: 11 },
            Relocatable { segment_index: 10, offset: 11 },
            Relocatable { segment_index: 10, offset: 11 },
        ]);

        // Serialize the pointers of the "ImplicitArgs" struct using the new memory segment.
        let result = kakarot_serde
            .serialize_pointers(
                "apply_transactions.ImplicitArgs",
                Relocatable { segment_index: 0, offset: 0 },
            )
            .expect("failed to serialize pointers");

        // Assert that the result matches the expected serialized struct members.
        assert_eq!(
            result,
            HashMap::from_iter([
                ("bitwise_ptr".to_string(), Some(Relocatable { segment_index: 10, offset: 11 })),
                ("chain_id".to_string(), Some(Relocatable { segment_index: 10, offset: 11 })),
                ("header".to_string(), Some(Relocatable { segment_index: 10, offset: 11 })),
                ("keccak_ptr".to_string(), Some(Relocatable { segment_index: 10, offset: 11 })),
                ("pedersen_ptr".to_string(), None),
                (
                    "range_check_ptr".to_string(),
                    Some(Relocatable { segment_index: 10, offset: 11 })
                ),
                ("state".to_string(), Some(Relocatable { segment_index: 10, offset: 11 })),
            ])
        );
    }

    #[test]
    fn test_serialize_no_pointer() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde();

        // Adding new zero values to check the effect of pointers vs non pointers
        let _ = kakarot_serde.runner.vm.gen_arg(&vec![
            Relocatable { segment_index: 0, offset: 0 },
            Relocatable { segment_index: 0, offset: 0 },
        ]);

        // Try to serialize
        let result = kakarot_serde
            .serialize_pointers(
                "apply_transactions.Args",
                Relocatable { segment_index: 0, offset: 0 },
            )
            .expect("failed to serialize pointers");

        // Assert that the result matches the expected serialized struct members.
        assert_eq!(
            result,
            HashMap::from_iter([
                ("tx_encoded".to_string(), None),
                // txs_len is not a pointer, so it should not be None
                ("txs_len".to_string(), Some(Relocatable { segment_index: 0, offset: 0 })),
            ])
        );
    }
}
