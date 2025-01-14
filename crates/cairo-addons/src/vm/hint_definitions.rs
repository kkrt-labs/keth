mod dict;
pub use dict::{copy_dict_segment, dict_new_empty};
mod hashdict;
pub use hashdict::{
    copy_hashdict_tracker_entry, get_preimage_for_key, hashdict_read, hashdict_write,
};

mod utils;
pub use utils::{b_le_a, bytes__eq__, nibble_remainder, value_set_or_zero};
