// Special types implementation for the Cairo type system.

// None Type Implementation:
// In this type system, None values are represented as null pointers (pointer to 0).
// For simple types of size 1, we use direct pointers (e.g., Uint*) rather than wrapping
// in an external struct to optimize memory usage. This allows checking if pointer == 0
// to determine if a value is None.
//
// For example:
// - A nullable Uint is represented as Uint* rather than struct { value: Uint* }
// - This saves memory by storing just [value] instead of [ptr_value, value]

// None values are just null pointers generally speaking (i.e. cast(my_var, felt) == 0)
// but we need to explicitly define None to be able to serialize/deserialize None
struct None {
    value: felt*,
}
