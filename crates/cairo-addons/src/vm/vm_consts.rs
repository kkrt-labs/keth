#![cfg(feature = "dynamic-hints")]
//! # Cairo VM Constants and Variable Access
//!
//! This module provides a bridge between Cairo variables in the Rust VM and Python code.
//! It implements a type-aware variable access system that mimics the behavior of the original
//! Python implementation of Cairo VM (VmConsts), allowing Python hints to access Cairo variables
//! with their full type information.
//!
//! Upon execution of a hint, the `ids` object is created and populated with the variables defined
//! in the hint using `create_vm_consts_dict`. The `ids` object is then used to access the variables
//! in the hint.
//!
//! There are four different types of variables:
//!
//! - Felt: Basic numeric values
//! - Relocatable: Memory addresses
//! - Struct: Composite types with named members
//! - Pointer: References to other types
//!
//! Struct and Pointer types can be dereferenced to access their members. The members are lazily
//! loaded from the program identifiers when the variable is accessed for efficiency.
//!
//! ## Key Components
//!
//! - `CairoVarType`: Represents the different types of Cairo variables (felt, relocatable, struct,
//!   pointer)
//! - `CairoVar`: Holds information about a Cairo variable's name, value, address, and type
//! - `PyVmConst`: Python-accessible wrapper for Cairo variables with type-aware access
//! - `PyVmConstsDict`: Dictionary-like object that stores Cairo variables and allows access by name
//!
//! ## Usage in Hints
//!
//! In Python hints, Cairo variables can be accessed through the `ids` dictionary:
//!
//! ```python
//! # Access a simple felt variable
//! value = ids.my_felt
//!
//! # Access a struct member
//! member_value = ids.my_struct.member_name
//!
//! # Access a pointer
//! ptr_value = ids.my_pointer
//!
//! # Dereference a pointer and access the value it points to
//! deref_value = ids.my_pointer.value
//!
//! # Get the address of a variable
//! address = ids.my_var.address_
//! ```
//!
//! ## Limitations
//!
//! - Mutation of `ids` variables is not supported

use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{
            get_ptr_from_var_name, get_relocatable_from_var_name,
        },
        hint_processor_definition::HintReference,
    },
    serde::deserialize_program::{ApTracking, Identifier, Member},
    types::relocatable::{MaybeRelocatable, Relocatable},
    vm::vm_core::VirtualMachine,
};
use pyo3::{prelude::*, types::PyList, IntoPyObjectExt};

use super::{dynamic_hint::DynamicHintError, relocatable::PyRelocatable};

/// Represents the different types of Cairo variables that can be accessed
#[derive(Debug, Clone)]
pub enum CairoVarType {
    Felt,
    Relocatable,
    Struct {
        name: String,
        members: HashMap<String, Member>,
        size: usize,
    },
    /// A pointer to another type
    Pointer {
        /// The type being pointed to
        pointee: Box<CairoVarType>,
    },
}

/// Holds information about a Cairo variable's name, value, and address
#[derive(Debug, Clone)]
pub struct CairoVar {
    pub name: String,
    pub value: MaybeRelocatable,
    pub address: Option<Relocatable>,
    pub var_type: CairoVarType,
}

/// Extracts struct information from identifiers and returns member details
/// # Returns
/// A tuple containing:
/// - A HashMap of member names to their definitions
/// - The size of the struct
fn get_struct_info_from_identifiers(
    identifiers: &HashMap<String, Identifier>,
    type_name: &str,
) -> Option<(HashMap<String, Member>, usize)> {
    // For pointer types, strip the trailing asterisks to get the base type
    let base_type_name = type_name.trim_end_matches('*');

    let identifier = identifiers.get(base_type_name)?;
    let members_map = identifier.members.as_ref()?;

    // Convert members to our format
    let mut members = HashMap::new();
    for (member_name, member_def) in members_map {
        members.insert(member_name.clone(), member_def.clone());
    }

    // Get the struct size or use default
    let size = identifier.size.unwrap_or(1);

    Some((members, size))
}

/// Create a CairoVarType instance based on the type name and identifiers
fn create_var_type(
    type_name: &str,
    identifiers: &HashMap<String, Identifier>,
) -> Result<CairoVarType, DynamicHintError> {
    if type_name == "felt" {
        return Ok(CairoVarType::Felt);
    }

    // Handle pointer types
    if type_name.ends_with('*') {
        let base_type = type_name.trim_end_matches('*');
        let asterisks_count = type_name.len() - base_type.len();

        // Create the innermost type
        let mut inner_type = if base_type == "felt" {
            CairoVarType::Relocatable
        } else {
            // For struct pointers, create a struct type
            match get_struct_info_from_identifiers(identifiers, base_type) {
                Some((members, size)) => {
                    CairoVarType::Struct { name: base_type.to_string(), members, size }
                }
                None => {
                    return Err(DynamicHintError::UnknownVariableType(format!(
                        "Could not get struct info for type '{}'",
                        base_type
                    )));
                }
            }
        };

        // Add pointer layers
        for _ in 0..asterisks_count {
            inner_type = CairoVarType::Pointer { pointee: Box::new(inner_type) };
        }

        return Ok(inner_type);
    }

    // It's a struct
    Ok(CairoVarType::Struct {
        name: type_name.to_string(),
        members: HashMap::new(), // Empty, will be lazy loaded
        size: 1,                 // Default size
    })
}

/// Python-accessible wrapper for Cairo variables that provides a behavior similar to
/// the original Python VmConsts implementation
///
/// See module-level documentation for usage examples.
#[pyclass(name = "VmConst", unsendable)]
pub struct PyVmConst {
    /// The variable information
    pub(crate) var: CairoVar,
    pub(crate) vm: *mut VirtualMachine,
    /// Reference to program identifiers for struct member resolution
    pub(crate) identifiers: Option<*const HashMap<String, Identifier>>,
}

// Non-Python methods
impl PyVmConst {
    /// Helper method to lazily load struct members from identifiers if needed
    /// Returns a new var_type with the loaded members if successful
    fn load_struct_members(&self, var_type: &CairoVarType) -> CairoVarType {
        // Check if we have identifiers
        let identifiers_ptr = match self.identifiers {
            Some(ptr) => ptr,
            None => return var_type.clone(),
        };

        let identifiers = unsafe { &*identifiers_ptr };

        match var_type {
            CairoVarType::Struct { name, members, size } => {
                // Only try to load if members is empty
                if members.is_empty() {
                    if let Some((new_members, new_size)) =
                        get_struct_info_from_identifiers(identifiers, name)
                    {
                        return CairoVarType::Struct {
                            name: name.clone(),
                            members: new_members,
                            size: new_size,
                        };
                    }
                }
                // Return the original if we couldn't load members
                CairoVarType::Struct { name: name.clone(), members: members.clone(), size: *size }
            }
            CairoVarType::Pointer { pointee } => {
                // If it's a pointer to a struct, try to load the struct members
                let new_pointee = Box::new(self.load_struct_members(pointee));
                CairoVarType::Pointer { pointee: new_pointee }
            }
            // For other types, just return a clone
            _ => var_type.clone(),
        }
    }

    /// Create a PyVmConst for a member of a struct
    fn create_member_var(
        &self,
        parent_name: &str,
        member_name: &str,
        member: &Member,
        member_addr: Relocatable,
    ) -> PyResult<PyObject> {
        // Check if we have identifiers
        let identifiers_ptr = match self.identifiers {
            Some(ptr) => ptr,
            None => {
                return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                    "Could not get identifiers when creating member '{}'",
                    member_name
                )))
            }
        };

        let identifiers = unsafe { &*identifiers_ptr };

        Python::with_gil(|py| {
            let vm = unsafe { &mut *self.vm };

            // Try to get the value from memory
            if let Some(value) = vm.get_maybe(&member_addr) {
                // Get member type from the member definition
                let member_type = create_var_type(member.cairo_type.as_ref(), identifiers)
                    .map_err(|e| {
                        PyErr::new::<pyo3::exceptions::PyAttributeError, _>(e.to_string())
                    })?;

                // Based on the type, return different Python objects
                match &member_type {
                    CairoVarType::Felt => {
                        // For felt types, return a Python int directly
                        match &value {
                            MaybeRelocatable::Int(felt) => {
                                Ok(felt.to_biguint().into_bound_py_any(py)?.into())
                            }
                            MaybeRelocatable::RelocatableValue(rel) => {
                                // If it's a relocatable but type is felt, still return the
                                // relocatable This can happen for
                                // range_check_ptr or __temp variables.
                                let py_rel = PyRelocatable { inner: *rel };
                                Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into())
                            }
                        }
                    }
                    CairoVarType::Relocatable => {
                        // For relocatable types, return a PyRelocatable directly
                        match &value {
                            MaybeRelocatable::RelocatableValue(rel) => {
                                let py_rel = PyRelocatable { inner: *rel };
                                Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into())
                            }
                            _ => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                                "Expected relocatable value, got {}",
                                value
                            ))),
                        }
                    }
                    _ => {
                        // For structs and pointers, use PyVmConst
                        let var = CairoVar {
                            name: format!("{}.{}", parent_name, member_name),
                            value,
                            address: Some(member_addr),
                            var_type: member_type,
                        };
                        let py_member =
                            PyVmConst { var, vm: self.vm, identifiers: self.identifiers };
                        Ok(Py::new(py, py_member)?.into_bound_py_any(py)?.into())
                    }
                }
            } else {
                Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                    "Member '{}' not found in memory",
                    member_name
                )))
            }
        })
    }
}

#[pymethods]
impl PyVmConst {
    /// Get the memory address of the variable
    #[getter]
    pub fn address_(&self, py: Python<'_>) -> PyResult<PyObject> {
        match self.var.address {
            Some(addr) => {
                let py_addr = PyRelocatable { inner: addr };
                Ok(Py::new(py, py_addr)?.into_bound_py_any(py)?.into())
            }
            None => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                "This variable does not have an address",
            )),
        }
    }

    /// Get a member of the variable if it's a struct
    pub fn __getattr__(&self, name: &str, py: Python<'_>) -> PyResult<PyObject> {
        if name == "address_" {
            return self.address_(py);
        }

        // // Create a possibly updated var_type with lazily loaded members
        // TODO: come back to this and see whether we can avoid loading the members here - having
        // them already available
        let var_type = self.load_struct_members(&self.var.var_type);

        // Handle different types
        match &var_type {
            CairoVarType::Struct { members, size, .. } => {
                // Check if the member exists and the struct has an address
                if let (Some(member), Some(addr)) = (members.get(name), self.var.address) {
                    // Extract offset as a numeric value we can use for address calculation
                    let offset_value = member.offset;
                    let member_addr = (addr + offset_value).map_err(|e| {
                        PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                    })?;

                    // Check if the member is a felt* and return a PyRelocatable directly
                    if member.cairo_type.as_str() == "felt*" {
                        let vm = unsafe { &mut *self.vm };
                        if let Some(MaybeRelocatable::RelocatableValue(rel)) =
                            vm.get_maybe(&member_addr)
                        {
                            let py_rel = PyRelocatable { inner: rel };
                            return Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into());
                        }
                    }

                    self.create_member_var(&self.var.name, name, member, member_addr)
                } else if name == "SIZE" {
                    // Special case for SIZE member
                    return Ok(size.into_bound_py_any(py)?.into());
                } else {
                    Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                        "Could not get member and address for struct '{}'",
                        name
                    )))
                }
            }
            CairoVarType::Pointer { pointee, .. } => {
                // If it's a pointer to a struct, we need to access the struct members directly
                if let CairoVarType::Struct { members, .. } = pointee.as_ref() {
                    // Check if the member exists in the struct
                    let vm = unsafe { &mut *self.vm };
                    if let (Some(member), Some(ptr_addr)) = (members.get(name), self.var.address) {
                        // For pointers, we need to:
                        // 1. Get the address the pointer points to
                        // 2. Calculate the member address by adding the offset to the pointer
                        let offset_value = member.offset;
                        let member_addr = (ptr_addr + offset_value).map_err(|e| {
                            PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                        })?;

                        // Check if the member is a felt* and return a PyRelocatable directly
                        if member.cairo_type.as_str() == "felt*" {
                            if let Some(MaybeRelocatable::RelocatableValue(rel)) =
                                vm.get_maybe(&member_addr)
                            {
                                let py_rel = PyRelocatable { inner: rel };
                                return Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into());
                            }
                        }

                        // 3. Create a member variable at that address
                        self.create_member_var(
                            &format!("(*{})", self.var.name),
                            name,
                            member,
                            member_addr,
                        )
                    } else {
                        Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                            "'{}' is not a member of the struct pointed to by '{}'",
                            name, self.var.name
                        )))
                    }
                } else {
                    Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                        "'{}' is not a pointer to a struct",
                        self.var.name
                    )))
                }
            }
            _ => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                "'{}' has no attribute '{}'",
                self.var.name, name
            ))),
        }
    }

    /// Get the type name of the variable
    pub fn type_name(&self) -> String {
        match &self.var.var_type {
            CairoVarType::Felt => "felt".to_string(),
            CairoVarType::Relocatable => "relocatable".to_string(),
            CairoVarType::Struct { name, .. } => name.clone(),
            CairoVarType::Pointer { pointee, .. } => match &**pointee {
                CairoVarType::Felt => "felt*".to_string(),
                CairoVarType::Relocatable => "relocatable*".to_string(),
                CairoVarType::Struct { name, .. } => format!("{}*", name),
                CairoVarType::Pointer { .. } => "pointer*".to_string(),
            },
        }
    }

    /// String representation
    pub fn __str__(&self) -> String {
        match &self.var.var_type {
            CairoVarType::Struct { name, .. } => {
                format!("{}({})", name, self.var.name)
            }
            CairoVarType::Pointer { pointee, .. } => match &**pointee {
                CairoVarType::Struct { name, .. } => {
                    format!("{}*({})", name, self.var.name)
                }
                _ => match &self.var.value {
                    MaybeRelocatable::Int(felt) => format!("{}", felt),
                    MaybeRelocatable::RelocatableValue(rel) => format!("{}", rel),
                },
            },
            _ => match &self.var.value {
                MaybeRelocatable::Int(felt) => format!("{}", felt),
                MaybeRelocatable::RelocatableValue(rel) => format!("{}", rel),
            },
        }
    }

    /// Repr string
    pub fn __repr__(&self) -> String {
        format!(
            "VmConst(name='{}', type={}, value={}, address={:?})",
            self.var.name,
            self.type_name(),
            self.__str__(),
            self.var.address
        )
    }

    /// Dereference this variable if it's a pointer
    pub fn deref(&self, py: Python<'_>) -> PyResult<PyObject> {
        // Check if this is a pointer type
        if let CairoVarType::Pointer { pointee, .. } = &self.var.var_type {
            // Get the relocatable value
            if let MaybeRelocatable::RelocatableValue(rel) = self.var.value {
                let vm = unsafe { &mut *self.vm };

                // Try to get the value at the pointer location
                if let Some(pointed_value) = vm.get_maybe(&rel) {
                    // Create a new CairoVar for the dereferenced value
                    let deref_var = CairoVar {
                        name: format!("*{}", self.var.name),
                        value: pointed_value,
                        address: Some(rel),
                        var_type: (**pointee).clone(),
                    };

                    let py_deref =
                        PyVmConst { var: deref_var, vm: self.vm, identifiers: self.identifiers };
                    return Ok(Py::new(py, py_deref)?.into_bound_py_any(py)?.into());
                } else {
                    return Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(format!(
                        "Could not dereference pointer: no value at address {}",
                        rel
                    )));
                }
            }
        }

        Err(PyErr::new::<pyo3::exceptions::PyTypeError, _>(format!(
            "Cannot dereference non-pointer value: {}",
            self.var.name
        )))
    }
}

/// A dictionary that stores Cairo variables and allows access by name
///
/// This class provides a Python-accessible dictionary-like interface for accessing
/// Cairo variables. It is the main entry point for Python hints to access Cairo
/// variables through the `ids` object.
///
/// # Implementation Details
///
/// The dictionary stores Python objects rather than raw Cairo variables to support
/// different representations based on the variable type:
///
/// - Simple felt values are stored as Python integers
/// - Relocatable values are stored as `PyRelocatable` objects
/// - Structs and pointers are stored as `PyVmConst` objects
///
/// This approach allows for a more natural Python interface while maintaining
/// type awareness and memory access capabilities.
///
/// # Usage in Hints
///
/// In Python hints, this dictionary is available as the `ids` object:
///
/// ```python
/// # Access variables
/// x = ids.x
/// y = ids.y
///
/// # List available variables
/// print(dir(ids))
///
/// # Check if a variable exists
/// if hasattr(ids, 'my_var'):
///     print(f"my_var exists: {ids.my_var}")
/// ```
/// See module-level documentation for more usage examples.
#[pyclass(name = "VmConstsDict", unsendable)]
pub struct PyVmConstsDict {
    /// Map of variable names to Python objects
    pub(crate) items: HashMap<String, Py<PyAny>>,
}

#[pymethods]
impl PyVmConstsDict {
    /// Get a variable by name
    pub fn __getattr__(&self, name: &str, py: Python<'_>) -> PyResult<PyObject> {
        match self.items.get(name) {
            Some(var) => {
                // Extract the Python object - this could be a PyVmConst or a native Python type
                // like int
                Ok(var.clone_ref(py).into_bound_py_any(py)?.into())
            }
            None => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                "'VmConstsDict' object has no attribute '{}'",
                name
            ))),
        }
    }

    /// Get a variable by dictionary access
    pub fn __getitem__(&self, name: &str, py: Python<'_>) -> PyResult<PyObject> {
        self.__getattr__(name, py)
    }

    /// Add or update a variable - accepts any Python object
    pub fn set_item(&mut self, key: &str, value: Py<PyAny>) {
        self.items.insert(key.to_string(), value);
    }

    /// Get all keys
    pub fn keys(&self, py: Python<'_>) -> PyResult<PyObject> {
        let keys = PyList::new(py, self.items.keys().map(|k| k.as_str()))?;
        Ok(keys.into())
    }

    /// Used for dir() in Python
    pub fn __dir__(&self, py: Python<'_>) -> PyResult<PyObject> {
        self.keys(py)
    }

    /// String representation
    pub fn __str__(&self) -> String {
        format!("VmConstsDict with {} items", self.items.len())
    }

    /// Repr string
    pub fn __repr__(&self) -> String {
        format!("VmConstsDict({:?})", self.items.keys().collect::<Vec<_>>())
    }
}

/// Creates a VmConstsDict from the variable accessible from the hint in `ids_data`.
pub fn create_vm_consts_dict(
    vm: &mut VirtualMachine,
    identifiers: &HashMap<String, Identifier>,
    ids_data: &HashMap<String, HintReference>,
    ap_tracking: &ApTracking,
    py: Python<'_>,
) -> Result<Py<PyVmConstsDict>, DynamicHintError> {
    let ids_dict = PyVmConstsDict { items: HashMap::new() };

    let py_ids_dict = Py::new(py, ids_dict)?;

    // Extract variables from ids_data. We basically just iterate over the ids_data and add the
    // variables to the dictionary - after properly handling the different types.
    // This function is not recursive, so it does not handle the inner members of structs. Instead,
    // these will be loaded lazily when the variable is accessed.
    for (name, reference) in ids_data {
        let cairo_type = reference.cairo_type.clone();

        // Get the address for the variable - we don't know its type yet.
        if let Ok(var_addr) = get_relocatable_from_var_name(name, vm, ids_data, ap_tracking) {
            if let Some(value) = vm.get_maybe(&var_addr) {
                // Based on the cairo_type and value, return different Python objects
                // to match the original Python VmConsts behavior.

                // Case 1: The variable is a felt
                if let Some(ref type_str) = cairo_type {
                    if type_str == "felt" {
                        // It's a felt - return Python int directly
                        match &value {
                            MaybeRelocatable::Int(felt) => {
                                // Convert to Python int
                                let py_int = felt.to_biguint().into_bound_py_any(py)?.into();
                                py_ids_dict.borrow_mut(py).items.insert(name.clone(), py_int);
                            }
                            MaybeRelocatable::RelocatableValue(rel) => {
                                // Special case for relocatable value with felt type
                                // Return the relocatable
                                let py_rel = PyRelocatable { inner: *rel };
                                let py_rel_obj = Py::new(py, py_rel)?.into_bound_py_any(py)?.into();
                                py_ids_dict.borrow_mut(py).items.insert(name.clone(), py_rel_obj);
                            }
                        }
                    } else if type_str.ends_with('*') {
                        // Case 2: The variable is a pointer
                        let address = get_ptr_from_var_name(name, vm, ids_data, ap_tracking)
                            .unwrap_or(var_addr);

                        // Create a CairoVarType based on the type_str
                        let var_type = create_var_type(type_str, identifiers).map_err(|e| {
                            PyErr::new::<pyo3::exceptions::PyAttributeError, _>(e.to_string())
                        })?;

                        // Case 2.1: The pointer is to a felt
                        if type_str == "felt*" {
                            // Pointer to a felt - return PyRelocatable directly
                            match &value {
                                MaybeRelocatable::RelocatableValue(rel) => {
                                    let py_rel = PyRelocatable { inner: *rel };
                                    let py_rel_obj =
                                        Py::new(py, py_rel)?.into_bound_py_any(py)?.into();
                                    py_ids_dict
                                        .borrow_mut(py)
                                        .items
                                        .insert(name.clone(), py_rel_obj);
                                }
                                _ => {
                                    // Unexpected case, but handle it by creating a PyVmConst
                                    let var = CairoVar {
                                        name: name.clone(),
                                        value: value.clone(),
                                        address: Some(address),
                                        var_type,
                                    };
                                    let py_var = PyVmConst {
                                        var,
                                        vm: vm as *mut VirtualMachine,
                                        identifiers: Some(
                                            identifiers as *const HashMap<String, Identifier>,
                                        ),
                                    };
                                    let py_var_obj =
                                        Py::new(py, py_var)?.into_bound_py_any(py)?.into();
                                    py_ids_dict.borrow_mut(py).set_item(name, py_var_obj);
                                }
                            }
                        } else {
                            // Case 2.2: The pointer is to a non-felt type
                            let var = CairoVar {
                                name: name.clone(),
                                value: value.clone(),
                                address: Some(address),
                                var_type,
                            };
                            let py_var = PyVmConst {
                                var,
                                vm: vm as *mut VirtualMachine,
                                identifiers: Some(
                                    identifiers as *const HashMap<String, Identifier>,
                                ),
                            };
                            let py_var_obj = Py::new(py, py_var)?.into_bound_py_any(py)?.into();
                            py_ids_dict.borrow_mut(py).set_item(name, py_var_obj);
                        }
                    } else {
                        // Case 3: The variable is a struct. In that case we return a PyVmConst
                        // that will load the struct members lazily when the variable is accessed.
                        let address =
                            get_relocatable_from_var_name(name, vm, ids_data, ap_tracking)
                                .unwrap_or(var_addr);

                        // Create a CairoVarType based on the type_str
                        let var_type = create_var_type(type_str, identifiers).map_err(|e| {
                            PyErr::new::<pyo3::exceptions::PyAttributeError, _>(e.to_string())
                        })?;

                        let var = CairoVar {
                            name: name.clone(),
                            value: value.clone(),
                            address: Some(address),
                            var_type,
                        };
                        let py_var = PyVmConst {
                            var,
                            vm: vm as *mut VirtualMachine,
                            identifiers: Some(identifiers as *const HashMap<String, Identifier>),
                        };
                        let py_var_obj = Py::new(py, py_var)?.into_bound_py_any(py)?.into();
                        py_ids_dict.borrow_mut(py).set_item(name, py_var_obj);
                    }
                } else {
                    return Err(DynamicHintError::UnknownVariableType(name.clone()));
                }
            }
        }
    }

    Ok(py_ids_dict)
}
