use cairo_vm::types::layout_name::LayoutName;
use pyo3::{prelude::*, FromPyObject};

#[derive(FromPyObject)]
pub struct PyLayout(pub String);

impl Default for PyLayout {
    fn default() -> Self {
        Self("plain".to_string())
    }
}

impl PyLayout {
    pub fn into_layout_name(self) -> PyResult<LayoutName> {
        match self.0.as_str() {
            "plain" => Ok(LayoutName::plain),
            "small" => Ok(LayoutName::small),
            "dex" => Ok(LayoutName::dex),
            "recursive" => Ok(LayoutName::recursive),
            "starknet" => Ok(LayoutName::starknet),
            "starknet_with_keccak" => Ok(LayoutName::starknet_with_keccak),
            "recursive_large_output" => Ok(LayoutName::recursive_large_output),
            "recursive_with_poseidon" => Ok(LayoutName::recursive_with_poseidon),
            "all_cairo" => Ok(LayoutName::all_cairo),
            "all_solidity" => Ok(LayoutName::all_solidity),
            _ => Err(PyErr::new::<pyo3::exceptions::PyValueError, _>("Invalid layout name")),
        }
    }
}
