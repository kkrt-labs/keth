use alloy_primitives::U256;
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

use crate::model::U128_BYTES_SIZE;

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

    /// Error variant indicating that a required field was not found during serialization.
    #[error("Missing required field '{field}' in serialization process.")]
    MissingField {
        /// The name of the missing field.
        field: String,
    },
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

    /// Serializes a Cairo VM `Uint256` structure (with `low` and `high` fields) into a Rust
    /// [`U256`] value.
    ///
    /// This function retrieves the `Uint256` struct from memory, extracts its `low` and `high`
    /// values, converts them into a big-endian byte representation, and combines them into a
    /// single [`U256`].
    pub fn serialize_uint256(&self, ptr: Relocatable) -> Result<U256, KakarotSerdeError> {
        // Fetches the `Uint256` structure from memory.
        let raw = self.serialize_pointers("Uint256", ptr)?;

        // Retrieves the `low` field from the deserialized struct, ensuring it's a valid integer.
        let low = match raw.get("low") {
            Some(Some(MaybeRelocatable::Int(value))) => value.clone(),
            _ => return Err(KakarotSerdeError::MissingField { field: "low".to_string() }),
        };

        // Retrieves the `high` field from the deserialized struct, ensuring it's a valid integer.
        let high = match raw.get("high") {
            Some(Some(MaybeRelocatable::Int(value))) => value.clone(),
            _ => return Err(KakarotSerdeError::MissingField { field: "high".to_string() }),
        };

        // Converts the `low` and `high` values into big-endian byte arrays.
        let high_bytes = high.to_bytes_be();
        let low_bytes = low.to_bytes_be();

        // Concatenates the last 16 bytes (128 bits) of the `high` and `low` byte arrays.
        //
        // This forms a 256-bit number, where:
        // - The `high` bytes make up the most significant 128 bits
        // - The `low` bytes make up the least significant 128 bits.
        let bytes = [&high_bytes[U128_BYTES_SIZE..], &low_bytes[U128_BYTES_SIZE..]].concat();

        // Creates a `U256` value from the concatenated big-endian byte array.
        Ok(U256::from_be_slice(&bytes))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use cairo_vm::types::{layout_name::LayoutName, program::Program};
    use std::str::FromStr;

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

        // Insert values in memory
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                MaybeRelocatable::Int(Felt252::ZERO),
                MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 10, offset: 11 }),
                MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 10, offset: 11 }),
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
                    Some(MaybeRelocatable::RelocatableValue(Relocatable {
                        segment_index: 10,
                        offset: 11
                    }))
                ),
                (
                    "bitwise_ptr".to_string(),
                    Some(MaybeRelocatable::RelocatableValue(Relocatable {
                        segment_index: 10,
                        offset: 11
                    }))
                ),
            ])
        );
    }

    #[test]
    fn test_serialize_null_no_pointer() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde();

        // Insert values in memory
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 10, offset: 11 }),
                MaybeRelocatable::Int(Felt252::ZERO),
                MaybeRelocatable::Int(Felt252::from(55)),
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
                (
                    "output_ptr".to_string(),
                    Some(MaybeRelocatable::RelocatableValue(Relocatable {
                        segment_index: 10,
                        offset: 11
                    }))
                ),
                // Not a pointer so that we shouldn't have a `None`
                ("range_check_ptr".to_string(), Some(MaybeRelocatable::Int(Felt252::ZERO))),
                ("bitwise_ptr".to_string(), Some(MaybeRelocatable::Int(Felt252::from(55)))),
            ])
        );
    }

    #[test]
    fn test_serialize_uint256_0() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde();

        // U256 to be serialized
        let x = U256::ZERO;

        // Setup with the high and low parts of the U256
        let low =
            Felt252::from_bytes_be_slice(&x.to_be_bytes::<{ U256::BYTES }>()[U128_BYTES_SIZE..]);
        let high =
            Felt252::from_bytes_be_slice(&x.to_be_bytes::<{ U256::BYTES }>()[0..U128_BYTES_SIZE]);

        // Insert values in memory
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![MaybeRelocatable::Int(low), MaybeRelocatable::Int(high)])
            .unwrap()
            .get_relocatable()
            .unwrap();

        // Serialize the Uint256 struct using the new memory segment.
        let result = kakarot_serde.serialize_uint256(base).expect("failed to serialize pointers");

        // Assert that the result is 0.
        assert_eq!(result, U256::ZERO);
    }

    #[test]
    fn test_serialize_uint256_valid() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde();

        // U256 to be serialized
        let x =
            U256::from_str("0x52f8f61201b2b11a78d6e866abc9c3db2ae8631fa656bfe5cb53668255367afb")
                .unwrap();

        // Setup with the high and low parts of the U256
        let low =
            Felt252::from_bytes_be_slice(&x.to_be_bytes::<{ U256::BYTES }>()[U128_BYTES_SIZE..]);
        let high =
            Felt252::from_bytes_be_slice(&x.to_be_bytes::<{ U256::BYTES }>()[0..U128_BYTES_SIZE]);

        // Insert values in memory
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![MaybeRelocatable::Int(low), MaybeRelocatable::Int(high)])
            .unwrap()
            .get_relocatable()
            .unwrap();

        // Serialize the Uint256 struct using the new memory segment.
        let result = kakarot_serde.serialize_uint256(base).expect("failed to serialize pointers");

        // Assert that the result matches the expected U256 value.
        assert_eq!(result, x);
    }

    #[test]
    fn test_serialize_uint256_not_int_high() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde();

        // U256 to be serialized
        let x = U256::MAX;

        // Setup with the high and low parts of the U256
        let low =
            Felt252::from_bytes_be_slice(&x.to_be_bytes::<{ U256::BYTES }>()[U128_BYTES_SIZE..]);
        // High is not an Int to trigger the error
        let high = Relocatable { segment_index: 10, offset: 11 };

        // Insert values in memory
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![MaybeRelocatable::Int(low), MaybeRelocatable::RelocatableValue(high)])
            .unwrap()
            .get_relocatable()
            .unwrap();

        // Try to serialize the Uint256 struct using the new memory segment.
        let result = kakarot_serde.serialize_uint256(base);

        // Assert that the result is an error with the expected missing field.
        match result {
            Err(KakarotSerdeError::MissingField { field }) => {
                assert_eq!(field, "high");
            }
            _ => panic!("Expected a missing field error, but got: {:?}", result),
        }
    }

    #[test]
    fn test_serialize_uint256_not_int_low() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde();

        // U256 to be serialized
        let x = U256::MAX;

        // Low is not an Int to trigger the error
        let low = Relocatable { segment_index: 10, offset: 11 };
        let high =
            Felt252::from_bytes_be_slice(&x.to_be_bytes::<{ U256::BYTES }>()[0..U128_BYTES_SIZE]);

        // Insert values in memory
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![MaybeRelocatable::RelocatableValue(low), MaybeRelocatable::Int(high)])
            .unwrap()
            .get_relocatable()
            .unwrap();

        // Try to serialize the Uint256 struct using the new memory segment.
        let result = kakarot_serde.serialize_uint256(base);

        // Assert that the result is an error with the expected missing field.
        match result {
            Err(KakarotSerdeError::MissingField { field }) => {
                assert_eq!(field, "low");
            }
            _ => panic!("Expected a missing field error, but got: {:?}", result),
        }
    }
}
