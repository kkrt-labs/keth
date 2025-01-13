mod dict;
pub use dict::copy_dict_segment;
mod hashdict;
pub use hashdict::{hashdict_read, hashdict_write};

mod utils;
pub use utils::{b_le_a, bytes__eq__};
