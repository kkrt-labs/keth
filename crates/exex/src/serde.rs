use crate::model::U128_BYTES_SIZE;
use alloy_primitives::U256;
use cairo_vm::{
    serde::deserialize_program::{Identifier, Location},
    types::{
        errors::math_errors::MathError,
        program::Program,
        relocatable::{MaybeRelocatable, Relocatable},
    },
    vm::{errors::memory_errors::MemoryError, runners::cairo_runner::CairoRunner},
    Felt252,
};
use std::collections::HashMap;
use thiserror::Error;

/// Represents the different types of values that can be stored in a pointer.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PointerValue {
    /// Relocatable value.
    Relocatable,
    /// Integer value.
    Felt,
}

/// Represents errors that can occur during the serialization and deserialization processes between
/// Cairo VM programs and Rust representations.
#[derive(Debug, Error, PartialEq)]
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

    /// Error variant indicating a Math error in Cairo VM operations
    #[error(transparent)]
    CairoVmMath(#[from] MathError),

    /// Error variant indicating a memory error in Cairo VM operations
    #[error(transparent)]
    CairoVmMemory(#[from] MemoryError),

    /// Error variant indicating that a required field was not found during serialization.
    #[error("Missing required field '{field}' in serialization process.")]
    MissingField {
        /// The name of the missing field.
        field: String,
    },

    /// Error variant indicating that an invalid value was encountered during serialization.
    #[error("Invalid value for field '{field}' in serialization process.")]
    InvalidFieldValue {
        /// The name of the invalid field.
        field: String,
    },

    /// Error variant indicating that no value was found at the specified memory location.
    #[error("No value at memory location: {location:?}")]
    NoValueAtMemoryLocation {
        /// The memory location that was expected to contain a value.
        location: Relocatable,
    },

    /// Error variant indicating that a pointer member is missing from a struct.
    #[error("The pointer member '{member}' is missing.")]
    MissingPointerMember {
        /// The name of the missing pointer member.
        member: String,
    },
    /// Error variant indicating that a pointer member has an incorrect value.
    #[error(
        "The pointer member '{member}' has an incorrect value. Got: {got_value:?},
    Expected: {expected_value:?}"
    )]
    IncorrectPointerValue {
        /// The name of the pointer member.
        member: String,
        /// The obtained value.
        got_value: Option<Option<MaybeRelocatable>>,
        /// The expected value type.
        expected_value: PointerValue,
    },

    /// Error indicating that a struct was not found during deserialization.
    #[error("Expected one struct named '{0}', found {1} matches.")]
    StructNotFound(String, usize),
}

/// Represents the types used in Cairo, including felt types, pointers, tuples, and structs.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum CairoType {
    /// A felt type, optionally associated with a location.
    Felt { location: Option<Location> },

    /// A pointer type that points to another [`CairoType`], with an optional location.
    Pointer { pointee: Box<CairoType>, location: Option<Location> },

    /// A tuple type that consists of multiple tuple items.
    Tuple { members: Vec<TupleItem>, has_trailing_comma: bool, location: Option<Location> },

    /// A struct type defined by its scope and an optional location.
    Struct { scope: ScopedName, location: Option<Location> },
}

impl CairoType {
    /// Creates a new [`CairoType::Struct`] with the specified scope and optional location.
    pub fn struct_type(scope: &str, location: Option<Location>) -> Self {
        Self::Struct { scope: ScopedName::from_string(scope), location }
    }

    /// Creates a new [`CairoType::Felt`] with an optional location.
    pub const fn felt_type(location: Option<Location>) -> Self {
        Self::Felt { location }
    }

    /// Creates a new [`CairoType::Pointer`] that points to a specified [`CairoType`].
    pub fn pointer_type(pointee: Self, location: Option<Location>) -> Self {
        Self::Pointer { pointee: Box::new(pointee), location }
    }

    /// Creates a new [`CairoType::Tuple`] from a vector of [`TupleItem`]s.
    pub const fn tuple_from_members(
        members: Vec<TupleItem>,
        has_trailing_comma: bool,
        location: Option<Location>,
    ) -> Self {
        Self::Tuple { members, has_trailing_comma, location }
    }

    /// Generate a [`CairoType`] from a string representation.
    #[allow(clippy::should_implement_trait)]
    pub fn from_str(name: &str) -> Self {
        match name {
            "felt" => Self::felt_type(None),
            _ => Self::struct_type(name, None),
        }
    }
}

/// Represents the different types of serialized values that can be extracted from the Cairo VM.
///
/// This enum provides a way to handle serialized data.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SerializedResult {
    /// A serialized 256-bit unsigned integer in the form of a [`U256`].
    U256(U256),

    /// A temporary data structure.
    ///
    /// This is a placeholder that should be removed or improved in the future.
    Tmp(Option<MaybeRelocatable>),

    /// A serialized struct in the form of a map from field names to serialized values.
    Struct(HashMap<String, Option<SerializedResult>>),
}

/// Represents an item in a tuple, consisting of an optional name, type, and location.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TupleItem {
    /// An optional string representing the name of the tuple item.
    pub name: Option<String>,

    /// The [`CairoType`] of the tuple item.
    pub typ: CairoType,

    /// An optional location associated with the tuple item.
    pub location: Option<Location>,
}

impl TupleItem {
    /// Creates a new [`TupleItem`] with an optional name, Cairo type, and location.
    pub const fn new(name: Option<String>, typ: CairoType, location: Option<Location>) -> Self {
        Self { name, typ, location }
    }
}

/// Represents a scoped name composed of a series of identifiers forming a path.
///
/// Example: `starkware.cairo.common.uint256.Uint256`.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ScopedName {
    /// A vector of strings representing the components of the scoped name.
    ///
    /// Each element in the vector corresponds to a segment of the name, separated by
    /// a dot (`.`).
    ///
    /// The first element is the top-level namespace, and subsequent elements represent
    /// sub-namespaces or types. This structure allows for easy manipulation and representation
    /// of names in a hierarchical format.
    pub path: Vec<String>,
}

impl ScopedName {
    /// Separator for the scope path.
    const SEPARATOR: &'static str = ".";

    /// Creates a [`ScopedName`] from a dot-separated string.
    pub fn from_string(scope: &str) -> Self {
        let path = if scope.is_empty() {
            vec![]
        } else {
            scope.split(Self::SEPARATOR).map(String::from).collect()
        };
        Self { path }
    }
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
        let Some(Some(MaybeRelocatable::Int(low))) = raw.get("low") else {
            return Err(KakarotSerdeError::MissingField { field: "low".to_string() })
        };

        // Retrieves the `high` field from the deserialized struct, ensuring it's a valid integer.
        let Some(Some(MaybeRelocatable::Int(high))) = raw.get("high") else {
            return Err(KakarotSerdeError::MissingField { field: "high".to_string() })
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

    /// Calculates the offset size for a given Cairo type.
    ///
    /// This function computes the offset based on the provided Cairo type:
    /// - For a tuple, it returns the number of elements in the tuple.
    /// - For a struct, it finds the identifier, then counts its members.
    ///   - If no members are found (`None`, which should never happen), it returns an offset of `0`
    ///     (an empty struct).
    /// - For all other types, it defaults to an offset of `1`.
    pub fn get_offset(&self, cairo_type: CairoType) -> Result<usize, KakarotSerdeError> {
        // Determine offset based on the Cairo type.
        match cairo_type {
            // For a tuple type, return the number of elements in the tuple.
            CairoType::Tuple { members, .. } => Ok(members.len()),

            // For a struct type, attempt to retrieve its identifier using the scope (struct's name
            // path).
            CairoType::Struct { scope, .. } => {
                // Retrieve the struct identifier and verify its presence in the program.
                let identifier =
                    self.get_identifier(&scope.path.join("."), Some("struct".to_string()))?;

                // Return the count of struct members.
                //
                // If members are `None`, return an offset of `0`, indicating an empty struct.
                // We should never encounter a struct with no members, so this is a safeguard.
                Ok(identifier.members.unwrap_or_default().len())
            }

            // For all other Cairo types, return a default offset of 1.
            _ => Ok(1),
        }
    }

    /// Serializes an optional value at the specified pointer in Cairo memory.
    ///
    /// In Cairo, a `model.Option` contains two fields:
    /// - `is_some`: A boolean field indicating whether the option contains a value.
    /// - `value`: The value contained in the option, if `is_some` is `true`.
    ///
    /// # Errors
    ///
    /// This function returns an error if:
    /// - The `is_some` field is not `0` or `1`.
    /// - The `is_some` field is `1`, but the `value` field is missing.
    pub fn serialize_option(
        &self,
        ptr: Relocatable,
    ) -> Result<Option<MaybeRelocatable>, KakarotSerdeError> {
        // Retrieve the serialized "Option" struct as a map of field names to values.
        let raw = self.serialize_pointers("model.Option", ptr)?;

        // Validate the "is_some" field.
        match raw.get("is_some") {
            Some(Some(MaybeRelocatable::Int(v))) if *v == Felt252::ZERO => Ok(None),
            Some(Some(MaybeRelocatable::Int(v))) if *v == Felt252::ONE => {
                // `is_some` is `1`, so check for "value" field.
                raw.get("value")
                    .cloned()
                    .ok_or_else(|| KakarotSerdeError::MissingField { field: "value".to_string() })
            }
            _ => Err(KakarotSerdeError::InvalidFieldValue { field: "is_some".to_string() }),
        }
    }

    /// Serializes the specified scope within the Cairo VM by attempting to extract
    /// a specific data structure based on the scope's path.
    pub fn serialize_scope(
        &self,
        scope: &ScopedName,
        scope_ptr: Relocatable,
    ) -> Result<Option<SerializedResult>, KakarotSerdeError> {
        // Retrieves the last segment of the scope path, which typically identifies the type.
        match scope.path.last().map(String::as_str) {
            Some("Uint256") => {
                self.serialize_uint256(scope_ptr).map(|v| Some(SerializedResult::U256(v)))
            }
            Some("KeccakBuiltinState") => {
                self.serialize_struct("KeccakBuiltinState", Some(scope_ptr))
            }
            _ => Ok(Some(SerializedResult::U256(U256::ZERO))),
        }
    }

    /// Serializes a dictionary from Cairo VM memory into a Rust [`HashMap`].
    ///
    /// This function reads a dictionary from the Cairo VM, where the dictionary is represented
    /// as a series of key-value pairs. The memory layout for each key-value entry is as follows:
    /// - The key is located at `dict_ptr`.
    /// - The previous value is located at `dict_ptr + 1`.
    /// - The actual value associated with the key is located at `dict_ptr + 2`.
    ///
    /// The function takes an optional `value_scope` to determine if the values need to be further
    /// serialized using a specific scope. If `value_scope` is provided and the value is a
    /// [`Relocatable`], the value will be serialized according to the given scope. Otherwise,
    /// the value will be added directly to the [`HashMap`].
    pub fn serialize_dict(
        &self,
        dict_ptr: Relocatable,
        value_scope: Option<String>,
        dict_size: Option<usize>,
    ) -> Result<HashMap<MaybeRelocatable, Option<SerializedResult>>, KakarotSerdeError> {
        // Determine the size of the dictionary. If not provided, get it from the VM.
        // We suppose here that the segment index is not negative so that the conversion from isize
        // to usize is safe.
        let dict_size = dict_size
            .or_else(|| self.runner.vm.get_segment_size(dict_ptr.segment_index.try_into().unwrap()))
            .unwrap_or_default();

        // If a `value_scope` is provided, try to find the corresponding identifier in the VM.
        let value_scope = value_scope
            .map(|v| self.get_identifier(&v, Some("struct".to_string())))
            .transpose()?
            .map(|id| id.full_name);

        // Create the output `HashMap` with an initial capacity for efficiency.
        let mut output = HashMap::with_capacity(dict_size / 3);

        // Iterate over the dictionary entries in steps of 3 to access keys and values.
        for dict_index in (0..dict_size).step_by(3) {
            // Calculate the pointer to the current key in the dictionary.
            let key_ptr = (dict_ptr + dict_index).unwrap();
            // Retrieve the key from the VM. If it doesn't exist, return an error.
            let key = self
                .runner
                .vm
                .get_maybe(&key_ptr)
                .ok_or(KakarotSerdeError::NoValueAtMemoryLocation { location: key_ptr })?;

            // The value is located at `key_ptr + 2`. Retrieve it from the VM.
            let value_ptr = self
                .runner
                .vm
                .get_maybe(&(key_ptr + 2usize).unwrap())
                .ok_or(KakarotSerdeError::NoValueAtMemoryLocation { location: key_ptr })?;

            // If `value_scope` is provided, we may need to serialize the value differently.
            if let Some(ref v) = value_scope {
                if matches!(value_ptr, MaybeRelocatable::RelocatableValue(_)) {
                    // If it is a `Relocatable`, serialize it using the scope.
                    let value = self.serialize_scope(
                        &ScopedName::from_string(&v.clone().unwrap_or_default()),
                        value_ptr.try_into().unwrap(),
                    )?;
                    // Convert the serialized value and insert it into the `HashMap`.
                    output.insert(key, value);
                } else {
                    // If the value is not a `Relocatable`, insert `None` as the value.
                    output.insert(key, None);
                }
            } else {
                // If no `value_scope` is provided, insert the value as-is.
                output.insert(key, Some(SerializedResult::Tmp(Some(value_ptr))));
            }
        }

        // Return the serialized dictionary.
        Ok(output)
    }

    /// Serializes the contents of the Kakarot OS `model.Memory` starting from a given pointer into
    /// a hexadecimal string.
    ///
    /// The `model.Memory` struct is a structured memory layout that contains the following fields:
    /// - `word_dict_start`: The pointer to a `DictAccess` used to store the memory's value at a
    ///   given index.
    /// - `word_dict`: The pointer to the end of the `DictAccess`.
    /// - `words_len`: Number of 32-byte words.
    ///
    /// This function reads and validates specific fields from a structured memory layout and
    /// serializes the contents into a compact, hexadecimal string format.
    ///
    /// The process involves:
    /// - Extracting key pointers,
    /// - Converting values, and handling potential errors gracefully.
    pub fn serialize_memory(&self, ptr: Relocatable) -> Result<String, KakarotSerdeError> {
        // Serialize pointers of the "model.Memory" struct
        let raw = self.serialize_pointers("model.Memory", ptr)?;

        // Extract and validate the `word_dict_start` pointer.
        // This should be a pointer to the start of the dictionary (`Relocatable`).
        let dict_start = match raw.get("word_dict_start") {
            Some(Some(MaybeRelocatable::RelocatableValue(ptr))) => *ptr,
            other => {
                return Err(KakarotSerdeError::IncorrectPointerValue {
                    member: "word_dict_start".to_string(),
                    got_value: other.cloned(),
                    expected_value: PointerValue::Relocatable,
                })
            }
        };

        // Extract and validate the `word_dict` pointer.
        // This should be a pointer to the end of the dictionary (`Relocatable`).
        let dict_end = match raw.get("word_dict") {
            Some(Some(MaybeRelocatable::RelocatableValue(word_dict))) => *word_dict,
            other => {
                return Err(KakarotSerdeError::IncorrectPointerValue {
                    member: "word_dict".to_string(),
                    got_value: other.cloned(),
                    expected_value: PointerValue::Relocatable,
                })
            }
        };

        // Serialize the dictionary from `dict_start` to `dict_end`.
        let memory_dict = self.serialize_dict(dict_start, None, Some((dict_end - dict_start)?))?;

        // Extract and validate the `words_len` field.
        // This should be a `Felt` value representing the number of 32-byte words.
        let words_len = match raw.get("words_len") {
            Some(Some(MaybeRelocatable::Int(words_len))) => words_len
                .to_string()
                .parse::<usize>()
                .map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(*words_len)))?,
            other => {
                return Err(KakarotSerdeError::IncorrectPointerValue {
                    member: "words_len".to_string(),
                    got_value: other.cloned(),
                    expected_value: PointerValue::Felt,
                })
            }
        };

        // Construct the serialized memory by iterating over the dictionary.
        // The memory is serialized as a string of 32-byte words.
        let serialized_memory = (0..words_len * 2)
            .map(|i| {
                if let Some(Some(SerializedResult::Tmp(Some(MaybeRelocatable::Int(value))))) =
                    memory_dict.get(&MaybeRelocatable::Int(i.into()))
                {
                    format!("{value:032x}")
                } else {
                    String::new()
                }
            })
            .collect::<String>();

        // Return the serialized memory as a single string.
        Ok(serialized_memory)
    }

    /// Serializes the contents of the `model.Stack` data structure from Cairo VM memory into a
    /// vector of serialized results.
    ///
    /// The `model.Stack` structure is expected to have the following fields:
    /// - `dict_ptr_start`: A pointer indicating the start of the dictionary in memory.
    /// - `dict_ptr`: A pointer indicating the end of the dictionary in memory.
    /// - `size`: The number of elements in the stack.
    ///
    /// This function deserializes the stack data by:
    /// 1. Extracting key-value pairs from the memory segment between `dict_ptr_start` and
    ///    `dict_ptr`.
    /// 2. The values are then serialized into a vector of [`SerializedResult`] instances. If the
    ///    stack contains values of type [`U256`].
    pub fn serialize_stack(
        &self,
        ptr: Relocatable,
    ) -> Result<Vec<Option<SerializedResult>>, KakarotSerdeError> {
        // Fetch the stack structure pointers from memory using the provided `ptr`.
        let stack = self.serialize_pointers("model.Stack", ptr)?;

        // Retrieve and validate the `dict_ptr_start` pointer from the `stack` structure.
        // - If the value is a valid `Relocatable` pointer, extract and use it.
        // - Otherwise, return an error.
        let dict_start = match stack.get("dict_ptr_start") {
            Some(Some(MaybeRelocatable::RelocatableValue(ptr))) => *ptr,
            other => {
                return Err(KakarotSerdeError::IncorrectPointerValue {
                    member: "dict_ptr_start".to_string(),
                    got_value: other.cloned(),
                    expected_value: PointerValue::Relocatable,
                })
            }
        };

        // Retrieve and validate the `dict_ptr` pointer from the `stack` structure.
        // - If the value is a valid `Relocatable` pointer, extract and use it.
        // - Otherwise, return an error.
        let dict_end = match stack.get("dict_ptr") {
            Some(Some(MaybeRelocatable::RelocatableValue(ptr))) => *ptr,
            other => {
                return Err(KakarotSerdeError::IncorrectPointerValue {
                    member: "dict_ptr".to_string(),
                    got_value: other.cloned(),
                    expected_value: PointerValue::Relocatable,
                })
            }
        };

        // Compute the size of the stack by retrieving and validating the `size` field.
        // - If the value is a valid `Felt` value, parse it into a `usize`.
        // - Otherwise, return an error.
        let size = match stack.get("size") {
            Some(Some(MaybeRelocatable::Int(size))) => size
                .to_string()
                .parse::<usize>()
                .map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(*size)))?,
            other => {
                return Err(KakarotSerdeError::IncorrectPointerValue {
                    member: "size".to_string(),
                    got_value: other.cloned(),
                    expected_value: PointerValue::Felt,
                })
            }
        };

        // Serialize the dictionary from `dict_ptr_start` to `dict_ptr`.
        // - The method converts the memory data between these pointers into a
        // `HashMap` of serialized values.
        // - The stack is expected to contain values of type `Uint256`.
        let stack_dict = self.serialize_dict(
            dict_start,
            Some("Uint256".to_string()),
            Some((dict_end - dict_start)?),
        )?;

        // Collect and return the serialized stack as a vector
        Ok((0..size)
            .map(|i| stack_dict.get(&MaybeRelocatable::Int(i.into())).cloned().unwrap_or(None))
            .collect())
    }

    /// Serializes a Cairo struct into a [`HashMap`] mapping field names to their serialized values.
    ///
    /// This method takes the name of a Cairo struct and an optional memory pointer to the
    /// struct's location in the Cairo VM memory.
    /// - If the pointer is `None`, the method returns an empty `[HashMap`].
    /// - If a pointer is provided, the method resolves the struct's members and serializes each
    ///   member according to its Cairo type.
    pub fn serialize_struct(
        &self,
        name: &str,
        ptr: Option<Relocatable>,
    ) -> Result<Option<SerializedResult>, KakarotSerdeError> {
        // Check if the provided pointer is `None`. If so, return `None`.
        if ptr.is_none() {
            return Ok(None);
        }

        // Initialize an empty `HashMap` to store the serialized struct members.
        let mut res = HashMap::new();

        // Attempt to retrieve the struct definition from the Cairo program.
        if let Some(members) = get_struct_definition(self.runner.get_program(), name)?.members {
            // Iterate over each member of the struct.
            for (name, member) in members {
                // Serialize the member and insert it into the `HashMap`.
                // - The member's type is determined using `CairoType::from_str`.
                // - The memory location is calculated by adding the member's offset to `ptr`.
                res.insert(
                    name,
                    self.serialize_inner(
                        &CairoType::from_str(&member.cairo_type),
                        (ptr.unwrap() + member.offset)?,
                        None,
                    )?,
                );
            }

            // Return the serialized struct as a `HashMap`.
            return Ok(Some(SerializedResult::Struct(res)));
        }

        // If the struct has no members, return `None`.
        Ok(None)
    }

    /// Serializes inner data types in Cairo by determining the type of data at a given pointer
    /// location.
    ///
    /// This method serializes data by checking its type.
    pub fn serialize_inner(
        &self,
        cairo_type: &CairoType,
        ptr: Relocatable,
        _length: Option<usize>,
    ) -> Result<Option<SerializedResult>, KakarotSerdeError> {
        // Match the Cairo type to determine how to serialize it.
        match cairo_type {
            CairoType::Felt { .. } => {
                // Retrieve the `MaybeRelocatable` value from memory at the specified pointer
                // location.
                Ok(Some(SerializedResult::Tmp(self.runner.vm.get_maybe(&ptr))))
            }
            CairoType::Struct { scope, .. } => self.serialize_scope(scope, ptr),
            // TODO: for now, we always generate a `Felt` serialized data type.
            // This is a placeholder for future implementation so that we can unit test.
            // We will need to implement the serialization of other data types.
            _ => Ok(Some(SerializedResult::Tmp(self.runner.vm.get_maybe(&ptr)))),
        }
    }
}

/// Function to get a struct definition by name.
pub fn get_struct_definition(
    program: &Program,
    struct_name: &str,
) -> Result<Identifier, KakarotSerdeError> {
    // Filter identifiers to match the struct name.
    let identifiers: Vec<&Identifier> = program
        .iter_identifiers()
        .filter(|(key, value)| {
            key.contains(struct_name) &&
                key.split('.').last() == struct_name.split('.').last() &&
                value.type_ == Some("struct".to_string())
        })
        .map(|(_, value)| value)
        .collect();

    // Ensure there is only one matching struct.
    if identifiers.len() != 1 {
        return Err(KakarotSerdeError::StructNotFound(struct_name.to_string(), identifiers.len()));
    }

    // Return the single matching struct.
    Ok(identifiers[0].clone())
}

#[cfg(test)]
mod tests {
    use super::*;
    use cairo_vm::{
        serde::deserialize_program::InputFile,
        types::{layout_name::LayoutName, program::Program},
    };
    use std::str::FromStr;

    /// Represents different test programs used for testing serialization and deserialization.
    enum TestProgram {
        KeccakAddUint256,
        ModelOption,
        ModelMemory,
        ModelStack,
    }

    impl TestProgram {
        /// Retrieves the byte representation of the selected test program.
        ///
        /// This method returns the contents of the JSON file associated with each test program,
        /// allowing the test runner to load the serialized test data directly into memory.
        const fn path(&self) -> &[u8] {
            match self {
                Self::KeccakAddUint256 => include_bytes!("../testdata/keccak_add_uint256.json"),
                Self::ModelOption => include_bytes!("../testdata/model_option.json"),
                Self::ModelMemory => include_bytes!("../testdata/model_memory.json"),
                Self::ModelStack => include_bytes!("../testdata/model_stack.json"),
            }
        }
    }

    fn setup_kakarot_serde(test_program: &TestProgram) -> KakarotSerde {
        // Load the valid program content from a JSON file
        let program_content = test_program.path();

        // Create a Program instance from the loaded bytes, specifying "main" as the entry point
        let program = Program::from_bytes(program_content, Some("main")).unwrap();

        // Initialize a CairoRunner with the created program and default parameters
        let runner = CairoRunner::new(&program, LayoutName::plain, None, false, false).unwrap();

        // Return an instance of KakarotSerde
        KakarotSerde { runner }
    }

    /// Helper function to set up a [`Program`] from a [`TestProgram`]
    fn setup_program(test_program: &TestProgram) -> Program {
        let program_content = test_program.path();
        Program::from_bytes(program_content, Some("main")).expect("Failed to load test program")
    }

    #[test]
    fn test_program_identifier_valid() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Check if the identifier "main" with expected type "function" is correctly retrieved
        assert_eq!(
            kakarot_serde.get_identifier("main", Some("function".to_string())).unwrap(),
            Identifier {
                pc: Some(96),
                type_: Some("function".to_string()),
                value: None,
                full_name: None,
                members: None,
                cairo_type: None,
                size: None
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
                cairo_type: Some("felt".to_string()),
                size: None
            }
        );
    }

    #[test]
    fn test_non_existent_identifier() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Test for a non-existent identifier
        let result =
            kakarot_serde.get_identifier("non_existent_struct", Some("function".to_string()));

        // Check if the error is valid and validate its parameters
        assert_eq!(
            result,
            Err(KakarotSerdeError::IdentifierNotFound {
                struct_name: "non_existent_struct".to_string(),
                expected_type: Some("function".to_string())
            })
        );
    }

    #[test]
    fn test_incorrect_identifier_usage() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Test for an identifier used incorrectly (not the last segment of the full name)
        let result = kakarot_serde.get_identifier("check_range", Some("struct".to_string()));

        // Check if the error is valid and validate its parameters
        assert_eq!(
            result,
            Err(KakarotSerdeError::IdentifierNotFound {
                struct_name: "check_range".to_string(),
                expected_type: Some("struct".to_string())
            })
        );
    }

    #[test]
    fn test_valid_identifier_incorrect_type() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Test for a valid identifier but with an incorrect type
        let result = kakarot_serde.get_identifier("main", Some("struct".to_string()));

        // Check if the error is valid and validate its parameters
        assert_eq!(
            result,
            Err(KakarotSerdeError::IdentifierNotFound {
                struct_name: "main".to_string(),
                expected_type: Some("struct".to_string())
            })
        );
    }

    #[test]
    fn test_identifier_with_multiple_matches() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Test for an identifier with multiple matches
        let result = kakarot_serde.get_identifier("ImplicitArgs", Some("struct".to_string()));

        // Check if the error is valid and validate its parameters
        assert_eq!(
            result,
            Err(KakarotSerdeError::MultipleIdentifiersFound {
                struct_name: "ImplicitArgs".to_string(),
                expected_type: Some("struct".to_string()),
                count: 6
            })
        );
    }

    #[test]
    fn test_serialize_pointer_not_struct() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Add a new memory segment to the virtual machine (VM).
        let base = kakarot_serde.runner.vm.add_memory_segment();

        // Attempt to serialize pointer with "main", expecting an IdentifierNotFound error.
        let result = kakarot_serde.serialize_pointers("main", base);

        // Assert that the result is an error with the expected struct name and type.
        assert_eq!(
            result,
            Err(KakarotSerdeError::IdentifierNotFound {
                struct_name: "main".to_string(),
                expected_type: Some("struct".to_string())
            })
        );
    }

    #[test]
    fn test_serialize_pointer_empty() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

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
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Setup
        let output_ptr = Felt252::ZERO;
        let range_check_ptr = kakarot_serde.runner.vm.add_memory_segment();
        let bitwise_ptr = kakarot_serde.runner.vm.add_memory_segment();

        // Insert values in memory
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
                ("bitwise_ptr".to_string(), Some(MaybeRelocatable::RelocatableValue(bitwise_ptr))),
            ])
        );
    }

    #[test]
    fn test_serialize_null_no_pointer() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Setup
        let output_ptr = Relocatable { segment_index: 10, offset: 11 };
        let range_check_ptr = Felt252::ZERO;
        let bitwise_ptr = Felt252::from(55);

        // Insert values in memory
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
                ("bitwise_ptr".to_string(), Some(MaybeRelocatable::Int(bitwise_ptr))),
            ])
        );
    }

    #[test]
    fn test_serialize_uint256_0() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

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
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

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
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

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
            _ => panic!("Expected a missing field error, but got: {result:?}"),
        }
    }

    #[test]
    fn test_serialize_uint256_not_int_low() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

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
        assert_eq!(result, Err(KakarotSerdeError::MissingField { field: "low".to_string() }));
    }

    #[test]
    fn test_get_offset_tuple() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Create Cairo types for Tuple members.
        let member1 = TupleItem::new(Some("a".to_string()), CairoType::felt_type(None), None);
        let member2 = TupleItem::new(
            Some("b".to_string()),
            CairoType::pointer_type(CairoType::felt_type(None), None),
            None,
        );

        // Create a Cairo type for a Tuple.
        let cairo_type = CairoType::tuple_from_members(vec![member1, member2], true, None);

        // Assert that the offset of the Tuple is equal to the number of members.
        assert_eq!(kakarot_serde.get_offset(cairo_type).unwrap(), 2);
    }

    #[test]
    fn test_get_offset_struct_invalid_identifier() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Create a Cairo type for a Struct with an invalid identifier.
        let cairo_type = CairoType::Struct {
            scope: ScopedName {
                path: vec!["an".to_string(), "invalid".to_string(), "path".to_string()],
            },
            location: None,
        };

        // Assert that the offset of the struct is an error due to the invalid identifier.
        assert_eq!(
            kakarot_serde.get_offset(cairo_type),
            Err(KakarotSerdeError::IdentifierNotFound {
                struct_name: "an.invalid.path".to_string(),
                expected_type: Some("struct".to_string()),
            })
        );
    }

    #[test]
    fn test_get_offset_struct_valid_identifier() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Create a Cairo type for a Struct with a valid identifier (3 members).
        let cairo_type = CairoType::Struct {
            scope: ScopedName { path: vec!["main".to_string(), "ImplicitArgs".to_string()] },
            location: None,
        };

        // Assert that the offset of the struct is equal to the number of members (3).
        assert_eq!(kakarot_serde.get_offset(cairo_type).unwrap(), 3);
    }

    #[test]
    fn test_get_offset_struct_valid_identifier_without_members() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Create a Cairo type for a Struct with a valid identifier (no members).
        let cairo_type = CairoType::Struct {
            scope: ScopedName { path: vec!["alloc".to_string(), "ImplicitArgs".to_string()] },
            location: None,
        };

        // Assert that the offset of the struct is 0 since the identifier has no members.
        assert_eq!(kakarot_serde.get_offset(cairo_type).unwrap(), 0);
    }

    #[test]
    fn test_get_offset_felt_pointer() {
        // Setup the KakarotSerde instance
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Create a Cairo type for a Felt.
        let cairo_type = CairoType::felt_type(None);

        // Assert that the offset of the Felt is 1 (value by default).
        assert_eq!(kakarot_serde.get_offset(cairo_type).unwrap(), 1);

        // Create a Cairo type for a Pointer.
        let pointee_type = CairoType::felt_type(None);
        let cairo_type = CairoType::pointer_type(pointee_type, None);

        // Assert that the offset of the Pointer is 1 (value by default).
        assert_eq!(kakarot_serde.get_offset(cairo_type).unwrap(), 1);
    }

    #[test]
    fn test_cairo_type_struct_type() {
        // A dummy scope name for the struct type.
        let scope_name = "starkware.cairo.common.uint256.Uint256";

        // Create a Cairo type for the struct.
        let cairo_type = CairoType::struct_type(scope_name, None);

        // Assert that the Cairo type is a struct with the correct scope name.
        assert_eq!(
            cairo_type,
            CairoType::Struct {
                scope: ScopedName {
                    path: vec![
                        "starkware".to_string(),
                        "cairo".to_string(),
                        "common".to_string(),
                        "uint256".to_string(),
                        "Uint256".to_string()
                    ]
                },
                location: None
            }
        );

        // Test with a dummy location
        let location = Some(Location {
            end_line: 100,
            end_col: 454,
            input_file: InputFile { filename: "test.cairo".to_string() },
            parent_location: None,
            start_line: 34,
            start_col: 234,
        });
        let cairo_type_with_location = CairoType::struct_type(scope_name, location.clone());
        assert_eq!(
            cairo_type_with_location,
            CairoType::Struct {
                scope: ScopedName {
                    path: vec![
                        "starkware".to_string(),
                        "cairo".to_string(),
                        "common".to_string(),
                        "uint256".to_string(),
                        "Uint256".to_string()
                    ]
                },
                location
            }
        );
    }

    #[test]
    fn test_cairo_type_felt() {
        // Create a Cairo type for a Felt.
        let cairo_type = CairoType::felt_type(None);

        // Assert that the Cairo type is a Felt with the correct location.
        assert_eq!(cairo_type, CairoType::Felt { location: None });

        // Test with a dummy location
        let location = Some(Location {
            end_line: 100,
            end_col: 454,
            input_file: InputFile { filename: "test.cairo".to_string() },
            parent_location: None,
            start_line: 34,
            start_col: 234,
        });
        let cairo_type_with_location = CairoType::felt_type(location.clone());
        assert_eq!(cairo_type_with_location, CairoType::Felt { location });
    }

    #[test]
    fn test_cairo_type_pointer() {
        // Create a Cairo type for a Pointer.
        let pointee_type = CairoType::felt_type(None);
        let cairo_type = CairoType::pointer_type(pointee_type.clone(), None);

        // Assert that the Cairo type is a Pointer with the correct pointee type.
        assert_eq!(
            cairo_type,
            CairoType::Pointer { pointee: Box::new(pointee_type), location: None }
        );

        // Test with a dummy location
        let location = Some(Location {
            end_line: 100,
            end_col: 454,
            input_file: InputFile { filename: "test.cairo".to_string() },
            parent_location: None,
            start_line: 34,
            start_col: 234,
        });
        let cairo_type_with_location =
            CairoType::pointer_type(CairoType::felt_type(None), location.clone());
        assert_eq!(
            cairo_type_with_location,
            CairoType::Pointer { pointee: Box::new(CairoType::Felt { location: None }), location }
        );
    }

    #[test]
    fn test_cairo_type_tuple() {
        // Create Cairo types for Tuple members.
        let member1 = TupleItem::new(Some("a".to_string()), CairoType::felt_type(None), None);
        let member2 = TupleItem::new(
            Some("b".to_string()),
            CairoType::pointer_type(CairoType::felt_type(None), None),
            None,
        );

        // Create a Cairo type for a Tuple.
        let cairo_type =
            CairoType::tuple_from_members(vec![member1.clone(), member2.clone()], true, None);

        // Assert that the Cairo type is a Tuple with the correct members and trailing comma flag.
        assert_eq!(
            cairo_type,
            CairoType::Tuple {
                members: vec![member1, member2],
                has_trailing_comma: true,
                location: None
            }
        );

        // Test with a dummy location
        let location = Some(Location {
            end_line: 100,
            end_col: 454,
            input_file: InputFile { filename: "test.cairo".to_string() },
            parent_location: None,
            start_line: 34,
            start_col: 234,
        });
        let cairo_type_with_location = CairoType::tuple_from_members(
            vec![TupleItem::new(None, CairoType::felt_type(None), None)],
            false,
            location.clone(),
        );
        assert_eq!(
            cairo_type_with_location,
            CairoType::Tuple {
                members: vec![TupleItem::new(None, CairoType::felt_type(None), None)],
                has_trailing_comma: false,
                location
            }
        );
    }

    #[test]
    fn test_serialize_inner_felt() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Setup
        let output_ptr = Relocatable { segment_index: 10, offset: 11 };
        let a = Felt252::ZERO;
        let b = Felt252::from(55);

        // Insert values in memory
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                MaybeRelocatable::RelocatableValue(output_ptr),
                MaybeRelocatable::Int(a),
                MaybeRelocatable::Int(b),
            ])
            .unwrap()
            .get_relocatable()
            .unwrap();

        // Serialize the Felt at the base memory segment.
        let result_relocatable =
            kakarot_serde.serialize_inner(&CairoType::Felt { location: None }, base, None);

        // Assert that the result matches the expected serialized Felt value (Relocatable).
        assert_eq!(
            result_relocatable,
            Ok(Some(SerializedResult::Tmp(Some(MaybeRelocatable::RelocatableValue(output_ptr)))))
        );

        // Serialize the Felt at the base memory segment with an offset of 1 to target
        // range_check_ptr.
        let result_int = kakarot_serde.serialize_inner(
            &CairoType::Felt { location: None },
            (base + 1usize).unwrap(),
            None,
        );

        // Assert that the result matches the expected serialized Felt value (Int).
        assert_eq!(result_int, Ok(Some(SerializedResult::Tmp(Some(MaybeRelocatable::Int(a))))));

        // Serialize the Felt at the base memory segment with an offset of 10 to target non-existing
        // data.
        let result_non_existing = kakarot_serde.serialize_inner(
            &CairoType::Felt { location: None },
            (base + 3usize).unwrap(),
            None,
        );

        // Assert that the result matches the expected serialized Felt value (None).
        assert_eq!(result_non_existing, Ok(Some(SerializedResult::Tmp(None))));
    }

    #[test]
    fn test_serialize_scope_uint256() {
        // Setup the KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Define a ScopedName ending in "Uint256"
        let scope = ScopedName {
            path: vec![
                "starkware".to_string(),
                "cairo".to_string(),
                "common".to_string(),
                "uint256".to_string(),
                "Uint256".to_string(),
            ],
        };

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

        // Serialize the scope with ScopedName "Uint256" and the generated pointer
        let result = kakarot_serde.serialize_scope(&scope, base);

        // Assert that the result matches the expected serialized U256 value
        assert_eq!(result, Ok(Some(SerializedResult::U256(x))));
    }

    #[test]
    fn test_serialize_option_some_value() {
        // Setup KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelOption);

        // Setup
        let is_some = Felt252::ONE;
        let value_ptr = kakarot_serde.runner.vm.add_memory_segment();

        // Insert values in memory
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                MaybeRelocatable::Int(is_some),
                MaybeRelocatable::RelocatableValue(value_ptr),
            ])
            .unwrap()
            .get_relocatable()
            .unwrap();

        // Serialize the Option struct using the new memory segment.
        let result =
            kakarot_serde.serialize_option(base).expect("failed to serialize model.Option");

        // Assert that the result matches the expected serialized struct members.
        assert_eq!(result, Some(MaybeRelocatable::RelocatableValue(value_ptr)));
    }

    #[test]
    fn test_serialize_option_none_value() {
        // Setup KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelOption);

        // Setup `is_some` as 0 to indicate None
        let is_some = Felt252::ZERO;

        // Insert values in memory
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![MaybeRelocatable::Int(is_some)])
            .unwrap()
            .get_relocatable()
            .unwrap();

        // Serialize the Option struct with `is_some` as `false`.
        let result =
            kakarot_serde.serialize_option(base).expect("failed to serialize model.Option");

        // Assert that the result is None since `is_some` is `false`.
        assert!(result.is_none());
    }

    #[test]
    fn test_serialize_option_missing_value_error() {
        // Setup KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelOption);

        // Set `is_some` to 1 but don't provide a `value` field to trigger an error.
        let is_some = Felt252::ONE;

        // Insert `is_some` in memory without a corresponding `value`.
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![MaybeRelocatable::Int(is_some)])
            .unwrap()
            .get_relocatable()
            .unwrap();

        // Serialize the Option struct expecting an error due to missing `value`.
        let result = kakarot_serde.serialize_option(base);

        // Assert that an error is returned for the missing `value` field.
        assert_eq!(result, Err(KakarotSerdeError::MissingField { field: "value".to_string() }));
    }

    #[test]
    fn test_serialize_option_invalid_is_some_error() {
        // Setup KakarotSerde instance
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelOption);

        // Set `is_some` to an invalid value (e.g., 2) to trigger an error.
        let invalid_is_some = Felt252::from(2);

        // Insert invalid `is_some` in memory.
        let base = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![MaybeRelocatable::Int(invalid_is_some)])
            .unwrap()
            .get_relocatable()
            .unwrap();

        // Serialize the Option struct expecting an error due to invalid `is_some`.
        let result = kakarot_serde.serialize_option(base);

        // Assert that an error is returned for the invalid `is_some` value.
        assert_eq!(
            result,
            Err(KakarotSerdeError::InvalidFieldValue { field: "is_some".to_string() })
        );
    }

    #[test]
    fn test_serialize_dict_empty() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Add a memory segment for the dictionary
        let dict_ptr = kakarot_serde.runner.vm.add_memory_segment();

        // Call serialize_dict with nothing in the dictionary
        let result_dict_size = kakarot_serde
            .serialize_dict(dict_ptr, None, Some(0))
            .expect("failed to serialize dict");

        // The result should be empty
        assert!(result_dict_size.is_empty());

        // Call serialize_dict with no members and no dict size
        let result_no_dict_size =
            kakarot_serde.serialize_dict(dict_ptr, None, None).expect("failed to serialize dict");

        // The result should also be empty
        assert!(result_no_dict_size.is_empty());
    }

    #[test]
    fn test_serialize_dict_with_values() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Insert key-value pairs into memory
        let key1 = MaybeRelocatable::Int(Felt252::from(1));
        let key2 = MaybeRelocatable::Int(Felt252::from(2));
        let key3 = MaybeRelocatable::Int(Felt252::from(3));
        let value1 = MaybeRelocatable::Int(Felt252::from(10));
        let value2 = MaybeRelocatable::Int(Felt252::from(20));
        let value3 =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 10, offset: 15 });

        let dict_ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                key1.clone(),
                MaybeRelocatable::Int(Felt252::ZERO),
                value1.clone(),
                key2.clone(),
                MaybeRelocatable::Int(Felt252::ZERO),
                value2.clone(),
                key3.clone(),
                MaybeRelocatable::Int(Felt252::ZERO),
                value3.clone(),
            ])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert key-value pairs into memory");

        // Call serialize_dict
        let result = kakarot_serde
            .serialize_dict(dict_ptr, None, Some(9))
            .expect("failed to serialize dict");

        // The result should contain the key-value pairs
        let expected = HashMap::from([
            (key1, Some(SerializedResult::Tmp(Some(value1)))),
            (key2, Some(SerializedResult::Tmp(Some(value2)))),
            (key3, Some(SerializedResult::Tmp(Some(value3)))),
        ]);
        assert_eq!(result, expected);
    }

    #[test]
    fn test_serialize_dict_with_null_pointer() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Insert a key with a null pointer as the value
        let key = MaybeRelocatable::Int(Felt252::from(1));
        let null_value = MaybeRelocatable::Int(Felt252::ZERO);
        let dict_ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![key.clone(), MaybeRelocatable::Int(Felt252::ZERO), null_value])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert key-value pairs into memory");

        // Call serialize_dict with a value scope
        let result = kakarot_serde
            .serialize_dict(dict_ptr, Some("main.ImplicitArgs".to_string()), Some(3))
            .expect("failed to serialize dict");

        // The result should have the key with a None value
        let expected = HashMap::from([(key, None)]);
        assert_eq!(result, expected);
    }

    #[test]
    fn test_serialize_dict_with_scope() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Insert key-value pairs into memory with a valid scope
        let key = MaybeRelocatable::Int(Felt252::from(1));
        let value_ptr = kakarot_serde.runner.vm.add_memory_segment();
        let dict_ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                key.clone(),
                MaybeRelocatable::Int(Felt252::ZERO),
                MaybeRelocatable::RelocatableValue(value_ptr),
            ])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert key-value pairs into memory");

        // Call serialize_dict with a valid scope
        let result = kakarot_serde
            .serialize_dict(dict_ptr, Some("main.ImplicitArgs".to_string()), Some(3))
            .expect("failed to serialize dict");

        // The result should serialize the scope correctly
        // NOTE: the Felt zero value is temporary until `serialize_scope` is implemented properly
        // After this, we will be able to implement `SerializedScope::as_serialized_result` properly
        let expected = HashMap::from([(key, Some(SerializedResult::U256(U256::ZERO)))]);
        assert_eq!(result, expected);
    }

    #[test]
    fn test_serialize_dict_with_invalid_scope() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Add a memory segment for the dictionary
        let dict_ptr = kakarot_serde.runner.vm.add_memory_segment();

        // Call serialize_dict with an invalid scope
        let result =
            kakarot_serde.serialize_dict(dict_ptr, Some("InvalidScope".to_string()), Some(3));

        // The result should be an error due to the invalid scope
        assert!(matches!(
            result,
            Err(KakarotSerdeError::IdentifierNotFound { struct_name, .. })
            if struct_name == "InvalidScope"
        ));
    }

    #[test]
    fn test_serialize_dict_with_invalid_size() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Insert only one key-value pair in memory to simulate an invalid size
        let key = MaybeRelocatable::Int(Felt252::from(1));
        let value = MaybeRelocatable::Int(Felt252::from(10));
        let dict_ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![key, MaybeRelocatable::Int(Felt252::ZERO), value])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert key-value pairs into memory");

        // Call serialize_dict with a size that exceeds the actual memory entries
        // Here, we use a size of 6 to ensure the loop tries to access a non-existent memory
        // location
        let result = kakarot_serde.serialize_dict(dict_ptr, None, Some(6));

        // The result should be an error due to the missing value at the memory location
        assert!(matches!(
            result,
            Err(KakarotSerdeError::NoValueAtMemoryLocation { location }) if location == (dict_ptr + 3usize).unwrap()
        ));
    }

    #[test]
    fn test_serialize_memory_empty() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelMemory);

        // Add an empty memory segment for the Stack
        let ptr = kakarot_serde.runner.vm.add_memory_segment();

        // Call serialize_memory on the empty memory
        let result = kakarot_serde.serialize_memory(ptr);

        // The result should be an empty string
        assert_eq!(
            result,
            Err(KakarotSerdeError::IncorrectPointerValue {
                member: "word_dict_start".to_string(),
                got_value: None,
                expected_value: PointerValue::Relocatable
            })
        );
    }

    #[test]
    fn test_serialize_memory_with_valid_pointers_simple() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelMemory);

        // Some dictionary pointers indicating:
        // - the start of the dictionary
        // - the end of the dictionary
        // - the length of the dictionary in words
        let dict_start =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 3 });
        let dict_end =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 15 });
        let words_len = MaybeRelocatable::Int(Felt252::from(2));

        // Key-value pairs to be inserted into the dictionary
        let key1 = MaybeRelocatable::Int(Felt252::from(0));
        let key2 = MaybeRelocatable::Int(Felt252::from(1));
        let key3 = MaybeRelocatable::Int(Felt252::from(2));
        let key4 = MaybeRelocatable::Int(Felt252::from(3));
        let value1 = MaybeRelocatable::Int(Felt252::from(10));
        let value2 = MaybeRelocatable::Int(Felt252::from(20));
        let value3 = MaybeRelocatable::Int(Felt252::from(30));
        let value4 = MaybeRelocatable::Int(Felt252::from(40));

        // Insert the dictionary key-value pairs into memory
        let dict_ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                dict_start,
                dict_end,
                words_len,
                key1,
                MaybeRelocatable::Int(Felt252::ZERO),
                value1,
                key2,
                MaybeRelocatable::Int(Felt252::ZERO),
                value2,
                key3,
                MaybeRelocatable::Int(Felt252::ZERO),
                value3,
                key4,
                MaybeRelocatable::Int(Felt252::ZERO),
                value4,
            ])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert key-value pairs into memory");

        // Call serialize_memory with the valid pointers
        let result = kakarot_serde.serialize_memory(dict_ptr).expect("failed to serialize memory");

        // The result should be a string representation of the serialized memory
        assert_eq!(result, "0000000000000000000000000000000a000000000000000000000000000000140000000000000000000000000000001e00000000000000000000000000000028".to_string());
    }

    #[test]
    fn test_serialize_memory_with_valid_pointers_holes() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelMemory);

        // Some dictionary pointers indicating:
        // - the start of the dictionary
        // - the end of the dictionary
        // - the length of the dictionary in words
        let dict_start =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 3 });
        let dict_end =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 15 });
        let words_len = MaybeRelocatable::Int(Felt252::from(3));

        // Key-value pairs to be inserted into the dictionary
        let key1 = MaybeRelocatable::Int(Felt252::from(0));
        let key2 = MaybeRelocatable::Int(Felt252::from(1));
        let key3 = MaybeRelocatable::Int(Felt252::from(2));
        let key4 = MaybeRelocatable::Int(Felt252::from(5));

        let value1 = MaybeRelocatable::Int(Felt252::from(10));
        let value2 = MaybeRelocatable::Int(Felt252::from(20));
        let value3 = MaybeRelocatable::Int(Felt252::from(30));
        let value4 = MaybeRelocatable::Int(Felt252::from(40));

        // Insert the dictionary key-value pairs into memory
        let dict_ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                dict_start,
                dict_end,
                words_len,
                key2,
                MaybeRelocatable::Int(Felt252::ZERO),
                value2,
                key1,
                MaybeRelocatable::Int(Felt252::ZERO),
                value1,
                key3,
                MaybeRelocatable::Int(Felt252::ZERO),
                value3,
                key4,
                MaybeRelocatable::Int(Felt252::ZERO),
                value4,
            ])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert key-value pairs into memory");

        // Call serialize_memory with the valid pointers
        let result = kakarot_serde.serialize_memory(dict_ptr).expect("failed to serialize memory");

        // The result should be a string representation of the serialized memory
        assert_eq!(result, "0000000000000000000000000000000a000000000000000000000000000000140000000000000000000000000000001e00000000000000000000000000000028".to_string());
    }

    #[test]
    fn test_serialize_memory_only_word_dict_start() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelMemory);

        // Insert only the `word_dict_start` pointer in memory
        let word_dict_start =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 3 });
        let ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![word_dict_start])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert word_dict_start into memory");

        // Call serialize_memory with incomplete dictionary pointers
        let result = kakarot_serde.serialize_memory(ptr);

        // The result should be an error due to the missing `word_dict`
        assert_eq!(
            result,
            Err(KakarotSerdeError::IncorrectPointerValue {
                member: "word_dict".to_string(),
                got_value: None,
                expected_value: PointerValue::Relocatable
            })
        );
    }

    #[test]
    fn test_serialize_memory_word_dict_start_non_relocatable_pointers() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelMemory);

        // Set `word_dict_start` as non-relocatable value
        let dict_start = MaybeRelocatable::Int(Felt252::from(123));
        let dict_end =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 15 });
        let ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![dict_start.clone(), dict_end])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert non-relocatable pointers into memory");

        // Call serialize_memory with non-relocatable pointers
        let result = kakarot_serde.serialize_memory(ptr);

        // The result should be an error indicating incorrect pointer values
        assert_eq!(
            result,
            Err(KakarotSerdeError::IncorrectPointerValue {
                member: "word_dict_start".to_string(),
                got_value: Some(Some(dict_start)),
                expected_value: PointerValue::Relocatable
            })
        );
    }

    #[test]
    fn test_serialize_memory_word_dict_end_non_relocatable_pointers() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelMemory);

        // Set`word_dict` as non-relocatable value
        let dict_start =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 15 });
        let dict_end = MaybeRelocatable::Int(Felt252::from(123));

        let ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![dict_start, dict_end.clone()])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert non-relocatable pointers into memory");

        // Call serialize_memory with non-relocatable pointers
        let result = kakarot_serde.serialize_memory(ptr);

        // The result should be an error indicating incorrect pointer values
        assert_eq!(
            result,
            Err(KakarotSerdeError::IncorrectPointerValue {
                member: "word_dict".to_string(),
                got_value: Some(Some(dict_end)),
                expected_value: PointerValue::Relocatable
            })
        );
    }

    #[test]
    fn test_serialize_memory_relocatable_words_len() {
        // Setup
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelMemory);

        // Some dictionary pointers indicating:
        // - the start of the dictionary
        // - the end of the dictionary
        // - we voluntarily set the length of the dictionary to be relocatable (not correct)
        let dict_start =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 3 });
        let dict_end =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 15 });
        let words_len =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 16 });

        // Key-value pairs to be inserted into the dictionary
        let key1 = MaybeRelocatable::Int(Felt252::from(0));
        let key2 = MaybeRelocatable::Int(Felt252::from(1));
        let key3 = MaybeRelocatable::Int(Felt252::from(2));
        let key4 = MaybeRelocatable::Int(Felt252::from(3));
        let value1 = MaybeRelocatable::Int(Felt252::from(10));
        let value2 = MaybeRelocatable::Int(Felt252::from(20));
        let value3 = MaybeRelocatable::Int(Felt252::from(30));
        let value4 = MaybeRelocatable::Int(Felt252::from(40));

        // Insert the dictionary key-value pairs into memory
        let dict_ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                dict_start,
                dict_end,
                words_len,
                key1,
                MaybeRelocatable::Int(Felt252::ZERO),
                value1,
                key2,
                MaybeRelocatable::Int(Felt252::ZERO),
                value2,
                key3,
                MaybeRelocatable::Int(Felt252::ZERO),
                value3,
                key4,
                MaybeRelocatable::Int(Felt252::ZERO),
                value4,
            ])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert key-value pairs into memory");

        // Call serialize_memory with missing `words_len`
        let result = kakarot_serde.serialize_memory(dict_ptr);

        // The result should be an error indicating the missing `words_len` field
        assert_eq!(
            result,
            Err(KakarotSerdeError::IncorrectPointerValue {
                member: "words_len".to_string(),
                got_value: Some(Some(MaybeRelocatable::RelocatableValue(Relocatable {
                    segment_index: 0,
                    offset: 16
                }))),
                expected_value: PointerValue::Felt
            })
        );
    }

    #[test]
    fn test_serialize_stack_empty() {
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelStack);

        // Add an empty memory segment for the Stack
        let ptr = kakarot_serde.runner.vm.add_memory_segment();

        // Call serialize_stack on the empty memory
        let result = kakarot_serde.serialize_stack(ptr);

        // The result should be an error for missing `dict_ptr_start`
        assert_eq!(
            result,
            Err(KakarotSerdeError::IncorrectPointerValue {
                member: "dict_ptr_start".to_string(),
                got_value: None,
                expected_value: PointerValue::Relocatable
            })
        );
    }

    #[test]
    fn test_serialize_stack_with_valid_pointers_basic() {
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelStack);

        // Some dictionary pointers indicating:
        // - the start of the dictionary
        // - the end of the dictionary
        // - the length of the dictionary
        let dict_start =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 3 });
        let dict_end =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 15 });
        let size = MaybeRelocatable::Int(Felt252::from(4));

        // Key-value pairs to be inserted into the dictionary
        let key1 = MaybeRelocatable::Int(Felt252::from(0));
        let key2 = MaybeRelocatable::Int(Felt252::from(1));
        let key3 = MaybeRelocatable::Int(Felt252::from(2));
        let key4 = MaybeRelocatable::Int(Felt252::from(3));
        let value1 =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 15 });
        let value2 = MaybeRelocatable::Int(Felt252::from(20));
        let value3 = MaybeRelocatable::Int(Felt252::from(30));
        let value4 =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 17 });

        // Two U256 values to be inserted into the stack
        let x =
            U256::from_str("0x52f8f61201b2b11a78d6e866abc9c3db2ae8631fa656bfe5cb53668255367afb")
                .unwrap();
        let y = U256::from_str(
            "18515461264373351373200002665853028612451056578545711640558177340181847433846",
        )
        .unwrap();

        // Transform the U256 values into Felt252 values
        let x_low =
            Felt252::from_bytes_be_slice(&x.to_be_bytes::<{ U256::BYTES }>()[U128_BYTES_SIZE..]);
        let x_high =
            Felt252::from_bytes_be_slice(&x.to_be_bytes::<{ U256::BYTES }>()[0..U128_BYTES_SIZE]);
        let y_low =
            Felt252::from_bytes_be_slice(&y.to_be_bytes::<{ U256::BYTES }>()[U128_BYTES_SIZE..]);
        let y_high =
            Felt252::from_bytes_be_slice(&y.to_be_bytes::<{ U256::BYTES }>()[0..U128_BYTES_SIZE]);

        // Insert into memory the dictionary:
        // - key-value pairs
        // - the U256 values
        let ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                dict_start,
                dict_end,
                size,
                key1,
                MaybeRelocatable::Int(Felt252::ZERO),
                value1,
                key2,
                MaybeRelocatable::Int(Felt252::ZERO),
                value2,
                key3,
                MaybeRelocatable::Int(Felt252::ZERO),
                value3,
                key4,
                MaybeRelocatable::Int(Felt252::ZERO),
                value4,
                MaybeRelocatable::Int(x_low),
                MaybeRelocatable::Int(x_high),
                MaybeRelocatable::Int(y_low),
                MaybeRelocatable::Int(y_high),
            ])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert key-value pairs into memory");

        // Call serialize_stack with valid pointers
        let result = kakarot_serde.serialize_stack(ptr).expect("failed to serialize stack");

        // The result should be a vector of serialized values
        assert_eq!(
            result,
            vec![Some(SerializedResult::U256(x)), None, None, Some(SerializedResult::U256(y))]
        );
    }

    #[test]
    fn test_serialize_stack_with_valid_pointers_mixed_order() {
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelStack);

        // Some dictionary pointers indicating:
        // - the start of the dictionary
        // - the end of the dictionary
        // - the length of the dictionary
        let dict_start =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 3 });
        let dict_end =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 15 });
        let size = MaybeRelocatable::Int(Felt252::from(4));

        // Key-value pairs to be inserted into the dictionary
        let key1 = MaybeRelocatable::Int(Felt252::from(0));
        let key2 = MaybeRelocatable::Int(Felt252::from(1));
        let key3 = MaybeRelocatable::Int(Felt252::from(2));
        let key4 = MaybeRelocatable::Int(Felt252::from(3));
        let value1 =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 15 });
        let value2 = MaybeRelocatable::Int(Felt252::from(20));
        let value3 = MaybeRelocatable::Int(Felt252::from(30));
        let value4 =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 17 });

        // Two U256 values to be inserted into the stack
        let x =
            U256::from_str("0x52f8f61201b2b11a78d6e866abc9c3db2ae8631fa656bfe5cb53668255367afb")
                .unwrap();
        let y = U256::from_str(
            "18515461264373351373200002665853028612451056578545711640558177340181847433846",
        )
        .unwrap();

        // Transform the U256 values into Felt252 values
        let x_low =
            Felt252::from_bytes_be_slice(&x.to_be_bytes::<{ U256::BYTES }>()[U128_BYTES_SIZE..]);
        let x_high =
            Felt252::from_bytes_be_slice(&x.to_be_bytes::<{ U256::BYTES }>()[0..U128_BYTES_SIZE]);
        let y_low =
            Felt252::from_bytes_be_slice(&y.to_be_bytes::<{ U256::BYTES }>()[U128_BYTES_SIZE..]);
        let y_high =
            Felt252::from_bytes_be_slice(&y.to_be_bytes::<{ U256::BYTES }>()[0..U128_BYTES_SIZE]);

        // Insert into memory the dictionary:
        // - key-value pairs (we voluntarily insert them in a mixed order to test the serialization)
        // - the U256 values
        let ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![
                dict_start,
                dict_end,
                size,
                key4,
                MaybeRelocatable::Int(Felt252::ZERO),
                value4,
                key3,
                MaybeRelocatable::Int(Felt252::ZERO),
                value3,
                key1,
                MaybeRelocatable::Int(Felt252::ZERO),
                value1,
                key2,
                MaybeRelocatable::Int(Felt252::ZERO),
                value2,
                MaybeRelocatable::Int(x_low),
                MaybeRelocatable::Int(x_high),
                MaybeRelocatable::Int(y_low),
                MaybeRelocatable::Int(y_high),
            ])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert key-value pairs into memory");

        // Call serialize_stack with valid pointers
        let result = kakarot_serde.serialize_stack(ptr).expect("failed to serialize stack");

        // The result should be a vector of serialized values
        assert_eq!(
            result,
            vec![Some(SerializedResult::U256(x)), None, None, Some(SerializedResult::U256(y))]
        );
    }

    #[test]
    fn test_serialize_stack_invalid_dict_ptr_start() {
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelStack);

        // Setup `dict_ptr_start` as a non-relocatable value
        let dict_start = MaybeRelocatable::Int(Felt252::from(123));
        let dict_end =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 15 });
        let size = MaybeRelocatable::Int(Felt252::from(2));

        // Insert the invalid `dict_ptr_start` into memory
        let ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![dict_start.clone(), dict_end, size])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert invalid dict_ptr_start into memory");

        // Call serialize_stack expecting an error
        let result = kakarot_serde.serialize_stack(ptr);

        // The result should be an error indicating the incorrect pointer value
        assert_eq!(
            result,
            Err(KakarotSerdeError::IncorrectPointerValue {
                member: "dict_ptr_start".to_string(),
                got_value: Some(Some(dict_start)),
                expected_value: PointerValue::Relocatable
            })
        );
    }

    #[test]
    fn test_serialize_stack_invalid_dict_ptr() {
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelStack);

        // Setup `dict_ptr` as a non-relocatable value
        let dict_start =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 3 });
        let dict_end = MaybeRelocatable::Int(Felt252::from(123));
        let size = MaybeRelocatable::Int(Felt252::from(2));

        // Insert the invalid `dict_ptr` into memory
        let ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![dict_start, dict_end.clone(), size])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert invalid dict_ptr into memory");

        // Call serialize_stack expecting an error
        let result = kakarot_serde.serialize_stack(ptr);

        // The result should be an error indicating the incorrect pointer value
        assert_eq!(
            result,
            Err(KakarotSerdeError::IncorrectPointerValue {
                member: "dict_ptr".to_string(),
                got_value: Some(Some(dict_end)),
                expected_value: PointerValue::Relocatable
            })
        );
    }

    #[test]
    fn test_serialize_stack_invalid_size() {
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::ModelStack);

        // Setup `size` as a relocatable value
        let dict_start =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 3 });
        let dict_end =
            MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 15 });
        let size = MaybeRelocatable::RelocatableValue(Relocatable { segment_index: 0, offset: 16 });

        // Insert the invalid `size` into memory
        let ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&vec![dict_start, dict_end, size.clone()])
            .unwrap()
            .get_relocatable()
            .expect("failed to insert invalid size into memory");

        // Call serialize_stack expecting an error
        let result = kakarot_serde.serialize_stack(ptr);

        // The result should be an error indicating the incorrect pointer value
        assert_eq!(
            result,
            Err(KakarotSerdeError::IncorrectPointerValue {
                member: "size".to_string(),
                got_value: Some(Some(size)),
                expected_value: PointerValue::Felt
            })
        );
    }

    #[test]
    fn test_get_struct_definition_single_match() {
        let program = setup_program(&TestProgram::KeccakAddUint256);
        let result = get_struct_definition(&program, "KeccakBuiltin");

        // Assert that the result is ok and contains the correct identifier
        assert!(result.is_ok());
        let identifier = result.unwrap();
        assert_eq!(
            identifier.full_name,
            Some("starkware.cairo.common.cairo_builtins.KeccakBuiltin".to_string())
        );
        assert_eq!(identifier.type_, Some("struct".to_string()));
    }

    #[test]
    fn test_get_struct_definition_no_match() {
        let program = setup_program(&TestProgram::ModelOption);
        let result = get_struct_definition(&program, "NonExistentStruct");

        // Assert that the result is an error indicating a type mismatch directly
        assert_eq!(
            result,
            Err(KakarotSerdeError::StructNotFound("NonExistentStruct".to_string(), 0))
        );
    }

    #[test]
    fn test_get_struct_definition_multiple_matches() {
        let program = setup_program(&TestProgram::ModelMemory);
        let result = get_struct_definition(&program, "ImplicitArgs");

        // Assert that the result is an error indicating multiple matches
        assert_eq!(result, Err(KakarotSerdeError::StructNotFound("ImplicitArgs".to_string(), 3)));
    }

    #[test]
    fn test_serialize_struct_none_pointer() {
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Test with a None pointer, expecting an empty vector as the result
        let result = kakarot_serde.serialize_struct("SomeStruct", None).unwrap();
        assert!(result.is_none());
    }

    #[test]
    fn test_serialize_struct_missing_struct_definition() {
        let kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Test with a struct name that doesn't exist in the program
        let ptr = Some(Relocatable { segment_index: 0, offset: 0 });
        let result = kakarot_serde.serialize_struct("NonExistentStruct", ptr);

        // Assert that the error indicates the struct was not found
        assert_eq!(
            result,
            Err(KakarotSerdeError::StructNotFound("NonExistentStruct".to_string(), 0))
        );
    }

    #[test]
    fn test_serialize_struct_valid_struct() {
        let mut kakarot_serde = setup_kakarot_serde(&TestProgram::KeccakAddUint256);

        // Helper function to generate a vector of `MaybeRelocatable::Int` from a range
        fn generate_memory_data(start: u64, count: usize) -> Vec<MaybeRelocatable> {
            (start..start + count as u64).map(|i| MaybeRelocatable::Int(Felt252::from(i))).collect()
        }

        // Setup the struct members and insert them into memory
        let ptr = kakarot_serde
            .runner
            .vm
            .gen_arg(&generate_memory_data(0, 18))
            .unwrap()
            .get_relocatable()
            .expect("failed to insert invalid dict_ptr_start into memory");

        // Helper function to create a `SerializedResult::Tmp` from a number
        fn create_tmp(value: u64) -> SerializedResult {
            SerializedResult::Tmp(Some(MaybeRelocatable::Int(Felt252::from(value))))
        }

        // Helper function to create a `HashMap` for struct serialization
        fn create_struct_data(start: u64) -> SerializedResult {
            SerializedResult::Struct(
                (0..8).map(|i| (format!("s{}", i), Some(create_tmp(start + i)))).collect(),
            )
        }

        // Test with a valid struct name
        let result = kakarot_serde
            .serialize_struct("KeccakBuiltin", Some(ptr))
            .expect("failed to serialize struct");

        // Expected input and output structs
        let input = create_struct_data(0);
        let output = create_struct_data(8);

        // Create the expected serialized result
        let expected = SerializedResult::Struct(HashMap::from([
            ("input".to_string(), Some(input)),
            ("output".to_string(), Some(output)),
        ]));

        // Assert that the result is as expected
        assert_eq!(result, Some(expected));
    }
}
