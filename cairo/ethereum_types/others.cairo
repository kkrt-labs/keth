// None values are just null pointers generally speaking (i.e. cast(my_var, felt) == 0)
// but we need to explicitly define None to be able to serialize/deserialize None
struct None {
    value: felt*,
}
