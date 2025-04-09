//! # Cairo VM Constants and Variable Access
//!
//! This module provides a bridge between Cairo variables in the Rust VM and Python code.
//! It implements a type-aware variable access system that mimics the behavior of the original
//! Python implementation of Cairo VM (VmConsts), allowing Python hints to access Cairo variables
//! with their full type information.
//!
//! ## Overview
//!
//! Upon execution of a hint, an `ids` object is created and populated with variables defined
//! in the hint using `create_vm_consts_dict`. This object serves as the primary interface
//! for Python hints to interact with Cairo variables. The system supports four variable types:
//!
//! - **Felt**: Basic numeric values (mapped to Python integers)
//! - **Relocatable**: Memory addresses (wrapped as `PyRelocatable`)
//! - **Struct**: Composite types with named members (wrapped as `PyVmConst`)
//! - **Pointer**: References to other types (wrapped as `PyVmConst`)
//!
//! Structs and pointers support member access and dereferencing, with members lazily loaded
//! from program identifiers for efficiency.
//!
//! ## Key Components
//!
//! - **`CairoVarType`**: Enum representing Cairo variable types
//! - **`CairoVar`**: Struct holding variable metadata (name, value, address, type)
//! - **`PyVmConst`**: Python-accessible wrapper for complex Cairo variables
//! - **`PyVmConstsDict`**: Dictionary-like interface for variable access in hints
//!
//! ## Usage in Python Hints
//!
//! ```python
//! # Access a simple felt variable
//! value = ids.my_felt
//!
//! # Access a struct member
//! member_value = ids.my_struct.member_name
//!
//! # Access a pointer and dereference it
//! ptr_value = ids.my_pointer
//! deref_value = ids.my_pointer.value
//!
//! # Get variable address
//! address = ids.my_var.address_
//! ```
use std::collections::HashMap;

use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{
            get_ptr_from_var_name, get_relocatable_from_var_name,
        },
        hint_processor_definition::HintReference,
        hint_processor_utils::get_maybe_relocatable_from_reference,
    },
    serde::deserialize_program::{ApTracking, Identifier, Member},
    types::relocatable::{MaybeRelocatable, Relocatable},
    vm::vm_core::VirtualMachine,
    Felt252,
};
use pyo3::{
    exceptions::{PyAttributeError, PyRuntimeError, PyTypeError},
    prelude::*,
    types::PyList,
    IntoPyObjectExt, PyResult,
};

use super::{
    maybe_relocatable::PyMaybeRelocatable, pythonic_hint::DynamicHintError,
    relocatable::PyRelocatable,
};

/// Represents the different types of Cairo variables that can be accessed in hints.
#[derive(Debug, Clone)]
pub enum CairoVarType {
    Felt,
    Relocatable,
    /// A composite type with named members.
    Struct {
        /// Fully qualified name of the struct type.
        name: String,
        /// Map of member names to their definitions (lazy-loaded).
        members: HashMap<String, Member>,
        /// Size of the struct in felts.
        size: usize,
    },
    /// A pointer to another type.
    Pointer {
        /// The type being pointed to.
        pointee: Box<CairoVarType>,
    },
}

/// Holds metadata about a Cairo variable for use in hints.
#[derive(Debug, Clone)]
pub struct CairoVar {
    /// Name of the variable as used in the hint.
    pub name: String,
    /// Current value of the variable, if available.
    pub value: Option<MaybeRelocatable>,
    /// Memory address of the variable, if assigned.
    pub address: Option<Relocatable>,
    /// Type information for the variable.
    pub var_type: CairoVarType,
}

/// Extracts struct member information from program identifiers.
///
/// # Arguments
/// - `identifiers`: Map of type names to their definitions.
/// - `type_name`: Name of the struct type to query.
///
/// # Returns
/// A tuple of `(members, size)` if successful, or `None` if the type is not found.
fn get_struct_info_from_identifiers(
    identifiers: &HashMap<String, Identifier>,
    type_name: &str,
) -> Option<(HashMap<String, Member>, usize)> {
    let base_type_name = type_name.trim_end_matches('*');
    let identifier = identifiers.get(base_type_name)?;
    let members_map = identifier.members.as_ref()?;

    let mut members = HashMap::new();
    for (member_name, member_def) in members_map {
        members.insert(member_name.clone(), member_def.clone());
    }

    let size = identifier.size.unwrap_or(1);
    Some((members, size))
}

/// Creates a `CairoVarType` from a type name and program identifiers.
///
/// # Arguments
/// - `type_name`: String representation of the type (e.g., "felt", "MyStruct", "felt*").
/// - `identifiers`: Program identifiers for resolving struct definitions.
///
/// # Returns
/// A `Result` containing the constructed type or a `DynamicHintError` if invalid.
fn create_var_type(
    type_name: &str,
    identifiers: &HashMap<String, Identifier>,
) -> Result<CairoVarType, DynamicHintError> {
    if type_name == "felt" {
        return Ok(CairoVarType::Felt);
    }

    if type_name.ends_with('*') {
        let base_type = type_name.trim_end_matches('*');
        let asterisks_count = type_name.len() - base_type.len();
        let mut inner_type = if base_type == "felt" {
            CairoVarType::Relocatable
        } else {
            match get_struct_info_from_identifiers(identifiers, base_type) {
                Some((members, size)) => {
                    CairoVarType::Struct { name: base_type.to_string(), members, size }
                }
                None => {
                    if base_type == "(fp_val: felt, pc_val: felt*)" {
                        // Manual handling of fp_val and pc_val, which causes issues in both VMs.
                        // return a dummy value instead.
                        return Ok(CairoVarType::Struct {
                            name: base_type.to_string(),
                            members: HashMap::new(),
                            size: 2,
                        });
                    }
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

    Ok(CairoVarType::Struct { name: type_name.to_string(), members: HashMap::new(), size: 1 })
}

/// Python-accessible wrapper for Cairo variables, mimicking the original Python `VmConsts`.
///
/// Provides attribute access, dereferencing, and type-aware behavior for structs and pointers.
#[pyclass(name = "VmConst", unsendable)]
#[derive(Debug, Clone)]
pub struct PyVmConst {
    /// The underlying Cairo variable data.
    pub(crate) var: CairoVar,
    /// Pointer to the VM for memory access.
    pub(crate) vm: *mut VirtualMachine,
    /// Optional pointer to identifiers for lazy member loading.
    pub(crate) identifiers: Option<*const HashMap<String, Identifier>>,
}

impl PyVmConst {
    /// Lazily loads struct members from identifiers if not already present.
    ///
    /// # Returns
    /// A new `CairoVarType` with loaded members, or a clone if loading fails.
    fn load_struct_members(&self, var_type: &CairoVarType) -> CairoVarType {
        let identifiers = match self.identifiers {
            Some(ptr) => unsafe { &*ptr },
            None => return var_type.clone(),
        };

        match var_type {
            CairoVarType::Struct { name, members, .. } if members.is_empty() => {
                if let Some((new_members, new_size)) =
                    get_struct_info_from_identifiers(identifiers, name)
                {
                    CairoVarType::Struct {
                        name: name.clone(),
                        members: new_members,
                        size: new_size,
                    }
                } else {
                    var_type.clone()
                }
            }
            CairoVarType::Pointer { pointee } => {
                CairoVarType::Pointer { pointee: Box::new(self.load_struct_members(pointee)) }
            }
            _ => var_type.clone(),
        }
    }

    /// Creates a `PyVmConst` for a struct member.
    ///
    /// # Arguments
    /// - `parent_name`: Name of the parent struct.
    /// - `member_name`: Name of the member to access.
    /// - `member`: Member definition from identifiers.
    /// - `member_addr`: Memory address of the member.
    ///
    /// # Returns
    /// A Python object representing the member (e.g., int, `PyRelocatable`, or `PyVmConst`).
    fn create_member_var(
        &self,
        parent_name: &str,
        member_name: &str,
        member: &Member,
        member_addr: Relocatable,
    ) -> PyResult<PyObject> {
        let identifiers = self.identifiers.ok_or_else(|| {
            PyAttributeError::new_err(format!(
                "Identifiers missing when accessing member '{}'",
                member_name
            ))
        })?;
        let identifiers = unsafe { &*identifiers };

        Python::with_gil(|py| {
            let vm = unsafe { &mut *self.vm };
            let value = vm.get_maybe(&member_addr).ok_or_else(|| {
                PyAttributeError::new_err(format!(
                    "Member '{}' not found in memory at {}",
                    member_name, member_addr
                ))
            })?;

            let member_type = create_var_type(member.cairo_type.as_ref(), identifiers)
                .map_err(|e| PyAttributeError::new_err(format!("Failed to create type: {}", e)))?;

            match member_type.clone() {
                CairoVarType::Felt => match value {
                    MaybeRelocatable::Int(felt) => {
                        Ok(felt.to_biguint().into_bound_py_any(py)?.into())
                    }
                    MaybeRelocatable::RelocatableValue(rel) => {
                        // If it's a relocatable but type is felt, still return the
                        // relocatable This can happen for
                        // range_check_ptr or __temp variables.
                        let py_rel = PyRelocatable { inner: rel };
                        Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into())
                    }
                },
                CairoVarType::Relocatable => match value {
                    // For relocatable types, return a PyRelocatable directly
                    MaybeRelocatable::RelocatableValue(rel) => {
                        let py_rel = PyRelocatable { inner: rel };
                        Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into())
                    }
                    _ => Err(PyAttributeError::new_err(format!(
                        "Expected relocatable value, got {}",
                        value
                    ))),
                },
                CairoVarType::Pointer { .. } => {
                    // The address of a pointer is the same as its value.
                    let var = CairoVar {
                        name: format!("{}.{}", parent_name, member_name),
                        value: Some(value.clone()),
                        address: self.get_address()?,
                        var_type: member_type,
                    };
                    let py_pointee = PyVmConst { var, vm: self.vm, identifiers: self.identifiers };
                    Ok(Py::new(py, py_pointee)?.into_bound_py_any(py)?.into())
                }
                CairoVarType::Struct { .. } => {
                    // For structs and pointers, use PyVmConst
                    let var = CairoVar {
                        name: format!("{}.{}", parent_name, member_name),
                        value: Some(value),
                        address: Some(member_addr),
                        var_type: member_type,
                    };
                    let py_member = PyVmConst { var, vm: self.vm, identifiers: self.identifiers };
                    Ok(Py::new(py, py_member)?.into_bound_py_any(py)?.into())
                }
            }
        })
    }

    /// Gets the effective address of the variable, dereferencing pointers if applicable.
    pub fn get_address(&self) -> PyResult<Option<Relocatable>> {
        match &self.var.var_type {
            CairoVarType::Pointer { .. } => {
                // The address of the pointer is the same as its value.
                // Note: if the variable is NOT a pointer (e.g. we cast something to a pointer),
                // like tempvar my_pointer_struct = MyPointerStruct(cast(0, felt*));
                // then the value is 0 and we should return `self.var.address`
                let pointer_value = self.var.value.as_ref();

                match pointer_value {
                    Some(MaybeRelocatable::RelocatableValue(rel)) => Ok(Some(*rel)),
                    Some(MaybeRelocatable::Int(_)) => Ok(self.var.address),
                    _ => Ok(None),
                }
            }
            _ => Ok(self.var.address),
        }
    }
}

#[pymethods]
impl PyVmConst {
    /// Gets the memory address of the variable as a `PyRelocatable`.
    #[getter]
    pub fn address_(&self, py: Python<'_>) -> PyResult<PyObject> {
        let addr = self
            .get_address()?
            .ok_or_else(|| PyAttributeError::new_err("This variable does not have an address"))?;
        let py_addr = PyRelocatable { inner: addr };
        Ok(Py::new(py, py_addr)?.into_bound_py_any(py)?.into())
    }

    /// Accesses attributes or members of the variable.
    pub fn __getattr__(&self, name: &str, py: Python<'_>) -> PyResult<PyObject> {
        if name == "address_" {
            return self.address_(py);
        }

        // Create a possibly updated var_type with lazily loaded members
        // TODO: come back to this and see whether we can avoid loading the members here - having
        // them already available
        let var_type = self.load_struct_members(&self.var.var_type);
        let vm = unsafe { &mut *self.vm };

        match var_type {
            CairoVarType::Felt => match &self.var.value {
                Some(MaybeRelocatable::Int(felt)) => {
                    Ok(felt.to_biguint().into_bound_py_any(py)?.into())
                }
                _ => Err(PyAttributeError::new_err(format!(
                    "Expected felt value, got {:?}",
                    self.var.value
                ))),
            },
            CairoVarType::Relocatable => match &self.var.value {
                Some(MaybeRelocatable::RelocatableValue(rel)) => {
                    let py_rel = PyRelocatable { inner: *rel };
                    Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into())
                }
                _ => Err(PyAttributeError::new_err(format!(
                    "Expected relocatable value, got {:?}",
                    self.var.value
                ))),
            },
            CairoVarType::Struct { members, size, .. } => {
                if name == "SIZE" {
                    return Ok(size.into_bound_py_any(py)?.into());
                }
                // Check if the member exists and the struct has an address
                let (member, addr) = match (members.get(name), self.var.address) {
                    (Some(m), Some(a)) => (m, a),
                    _ => {
                        return Err(PyAttributeError::new_err(format!(
                            "Struct has no member '{}' or no address",
                            name
                        )))
                    }
                };
                let member_addr = (addr + member.offset).map_err(|e| {
                    PyRuntimeError::new_err(format!("Address calculation failed: {}", e))
                })?;

                // Check if the member is a felt* and return a PyRelocatable directly
                if member.cairo_type.as_str() == "felt*" {
                    match vm.get_maybe(&member_addr) {
                        Some(MaybeRelocatable::RelocatableValue(rel)) => {
                            let py_rel = PyRelocatable { inner: rel };
                            return Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into());
                        }
                        Some(MaybeRelocatable::Int(value)) => {
                            return Ok(value.to_biguint().into_bound_py_any(py)?.into());
                        }
                        _ => panic!(
                            "Expected relocatable or felt value, got {:?}",
                            vm.get_maybe(&member_addr)
                        ),
                    }
                }
                self.create_member_var(&self.var.name, name, member, member_addr)
            }
            CairoVarType::Pointer { ref pointee } => {
                // If it's a pointer to a struct, we need to access the struct members directly
                if let CairoVarType::Struct { members, .. } = pointee.as_ref() {
                    let member = members.get(name).ok_or_else(|| {
                        PyAttributeError::new_err(format!(
                            "Struct pointed to by '{}' has no member '{}'",
                            self.var.name, name
                        ))
                    })?;
                    // For pointers, we need to:
                    // 1. Get the address the pointer points to
                    // 2. Calculate the member address by adding the offset to the pointer
                    let ptr_addr = self
                        .get_address()?
                        .ok_or_else(|| PyAttributeError::new_err("Pointer has no address"))?;
                    let member_addr = (ptr_addr + member.offset).map_err(|e| {
                        PyRuntimeError::new_err(format!("Address calculation failed: {}", e))
                    })?;

                    // Check if the member is a felt* and return a PyRelocatable directly
                    if member.cairo_type.as_str() == "felt*" {
                        match vm.get_maybe(&member_addr) {
                            Some(MaybeRelocatable::RelocatableValue(rel)) => {
                                let py_rel = PyRelocatable { inner: rel };
                                return Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into());
                            }
                            Some(MaybeRelocatable::Int(value)) => {
                                return Ok(value.to_biguint().into_bound_py_any(py)?.into());
                            }
                            _ => panic!(
                                "Expected relocatable or felt value, got {:?}",
                                vm.get_maybe(&member_addr)
                            ),
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
                    Err(PyAttributeError::new_err(format!(
                        "'{}' is not a pointer to a struct",
                        self.var.name
                    )))
                }
            }
        }
    }

    /// Gets the type path as a list of strings (for structs only).
    #[getter]
    pub fn type_path(&self) -> Option<Vec<String>> {
        match &self.var.var_type {
            CairoVarType::Struct { name, .. } => Some(name.split('.').map(String::from).collect()),
            CairoVarType::Pointer { pointee, .. } => match &**pointee {
                CairoVarType::Struct { name, .. } => {
                    Some(name.split('.').map(String::from).collect())
                }
                _ => None,
            },
            _ => None,
        }
    }

    /// Checks if the variable is a pointer.
    pub fn is_pointer(&self) -> bool {
        matches!(self.var.var_type, CairoVarType::Pointer { .. })
    }

    /// Gets the type name as a string.
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

    /// Returns a string representation of the variable.
    pub fn __str__(&self) -> String {
        match &self.var.var_type {
            CairoVarType::Struct { name, .. } => format!("{}({})", name, self.var.name),
            CairoVarType::Pointer { pointee, .. } => match &**pointee {
                CairoVarType::Struct { name, .. } => format!("{}*({})", name, self.var.name),
                _ => self.var.value.as_ref().map_or("None".to_string(), |v| v.to_string()),
            },
            _ => self.var.value.as_ref().map_or("None".to_string(), |v| v.to_string()),
        }
    }

    /// Returns a detailed representation string.
    pub fn __repr__(&self) -> String {
        format!(
            "VmConst(name='{}', path={:?}, address={:?})",
            self.var.name,
            self.type_path(),
            self.get_address().expect("PyVmConst does not have an address").unwrap()
        )
    }

    /// Dereferences a pointer variable.
    pub fn deref(&self, py: Python<'_>) -> PyResult<PyObject> {
        if let CairoVarType::Pointer { pointee } = &self.var.var_type {
            let rel = match self.var.value {
                Some(MaybeRelocatable::RelocatableValue(r)) => r,
                _ => {
                    return Err(PyTypeError::new_err(format!(
                        "Cannot dereference '{}': not a pointer with a relocatable value",
                        self.var.name
                    )))
                }
            };
            let vm = unsafe { &mut *self.vm };
            let pointed_value = vm.get_maybe(&rel).ok_or_else(|| {
                PyRuntimeError::new_err(format!("Could not dereference pointer at {}", rel))
            })?;

            let deref_var = CairoVar {
                name: format!("*{}", self.var.name),
                value: Some(pointed_value),
                address: Some(rel),
                var_type: (**pointee).clone(),
            };
            let py_deref = PyVmConst { var: deref_var, vm: self.vm, identifiers: self.identifiers };
            Ok(Py::new(py, py_deref)?.into_bound_py_any(py)?.into())
        } else {
            Err(PyTypeError::new_err(format!("Cannot dereference non-pointer '{}'", self.var.name)))
        }
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
    /// Map of variable names to their Python representations.
    pub(crate) items: HashMap<String, Py<PyAny>>,
    /// Pointer to the VM for memory operations.
    pub(crate) vm: *mut VirtualMachine,
}

#[pymethods]
impl PyVmConstsDict {
    /// Gets a variable by name.
    pub fn __getattr__(&self, name: &str, py: Python<'_>) -> PyResult<PyObject> {
        self.items
            .get(name)
            .ok_or_else(|| PyAttributeError::new_err(format!("No variable '{}'", name)))
            .and_then(|var| {
                let bound_py = var.clone_ref(py).into_bound_py_any(py)?;
                Ok(bound_py.into())
            })
    }

    /// Sets a variable's value if it exists and is unassigned.
    pub fn __setattr__(&mut self, name: &str, value: Py<PyAny>, py: Python<'_>) -> PyResult<()> {
        let var = self
            .items
            .get_mut(name)
            .ok_or_else(|| PyAttributeError::new_err(format!("No variable '{}' to set", name)))?;
        let mut vm_const = var
            .downcast_bound::<PyVmConst>(py)
            .map_err(|_| {
                PyAttributeError::new_err(format!("Variable '{}' is not a VmConst", name))
            })?
            .as_unbound()
            .borrow_mut(py);

        if vm_const.var.value.is_some() {
            return Err(PyAttributeError::new_err(format!(
                "Cannot set '{}': already has a value",
                name
            )));
        }

        let maybe_relocatable = value.extract::<PyMaybeRelocatable>(py)?;
        vm_const.var.value = Some(maybe_relocatable.clone().into());
        let vm = unsafe { &mut *self.vm };
        vm.insert_value::<MaybeRelocatable>(
            vm_const
                .var
                .address
                .ok_or_else(|| PyRuntimeError::new_err(format!("No address for '{}'", name)))?,
            maybe_relocatable.into(),
        )
        .map_err(|e| PyRuntimeError::new_err(e.to_string()))?;
        Ok(())
    }

    /// Dictionary-style variable access.
    pub fn __getitem__(&self, name: &str, py: Python<'_>) -> PyResult<PyObject> {
        self.__getattr__(name, py)
    }

    /// Adds or updates a variable in the dictionary.
    pub fn set_item(&mut self, key: &str, value: Py<PyAny>) {
        self.items.insert(key.to_string(), value);
    }

    /// Lists all variable names.
    pub fn keys(&self, py: Python<'_>) -> PyResult<PyObject> {
        Ok(PyList::new(py, self.items.keys().map(|k| k.as_str()))?.into())
    }

    /// Supports Python's `dir()` function.
    pub fn __dir__(&self, py: Python<'_>) -> PyResult<PyObject> {
        self.keys(py)
    }

    /// String representation.
    pub fn __str__(&self) -> String {
        format!("VmConstsDict with {} items", self.items.len())
    }

    /// Detailed representation.
    pub fn __repr__(&self) -> String {
        format!("VmConstsDict({:?})", self.items.keys().collect::<Vec<_>>())
    }
}

/// Creates a `PyVmConstsDict` from hint variables.
///
/// # Arguments
/// - `vm`: The Cairo virtual machine instance.
/// - `identifiers`: Program identifiers for type resolution.
/// - `ids_data`: Hint references mapping names to variable metadata.
/// - `ap_tracking`: AP Tracking data
/// - `py`: Python GIL token.
///
/// # Returns
/// A `PyResult` containing the constructed dictionary or a `DynamicHintError`.
pub fn create_vm_consts_dict(
    vm: &mut VirtualMachine,
    identifiers: &HashMap<String, Identifier>,
    ids_data: &HashMap<String, HintReference>,
    ap_tracking: &ApTracking,
    constants: &HashMap<String, Felt252>,
    hint_accessible_scopes: &Vec<String>,
    py: Python<'_>,
) -> Result<Py<PyVmConstsDict>, DynamicHintError> {
    let ids_dict = PyVmConstsDict { items: HashMap::new(), vm: vm as *mut VirtualMachine };
    let py_ids_dict = Py::new(py, ids_dict)?;

    // Process constants and make them accessible in Python hints
    // Constants are in the form {"module.name": value} and are accessible if their module
    // is in the hint_accessible_scopes
    for (full_name, value) in constants {
        let parts: Vec<_> = full_name.split('.').collect();
        let const_name = parts.last().unwrap_or(&"").to_string();
        let module_path = parts[..parts.len() - 1].join(".");

        // Check if constant is directly accessible from current scope
        if hint_accessible_scopes.iter().any(|scope| module_path == *scope) {
            py_ids_dict
                .borrow_mut(py)
                .items
                .insert(const_name.to_string(), value.to_biguint().into_bound_py_any(py)?.into());
            continue;
        }

        // Check if constant is accessible through an alias in any accessible scope
        for scope in hint_accessible_scopes {
            let alias_path = format!("{}.{}", scope, const_name);

            if let Some(identifier) = identifiers.get(&alias_path) {
                if let Some(destination) = &identifier.destination {
                    if let Some(resolved_value) = constants.get(destination) {
                        py_ids_dict.borrow_mut(py).items.insert(
                            const_name.to_string(),
                            resolved_value.to_biguint().into_bound_py_any(py)?.into(),
                        );
                        break;
                    }
                }
            }
        }
    }

    for (name, reference) in ids_data {
        // Some internal variables, prefixed with `__temp`, that we skip.
        if name.starts_with("__temp") {
            continue;
        }
        let cairo_type = reference.cairo_type.as_ref().ok_or_else(|| {
            DynamicHintError::UnknownVariableType(format!("No type for '{}'", name))
        })?;
        let var_addr = match get_relocatable_from_var_name(name, vm, ids_data, ap_tracking) {
            Ok(addr) => addr,
            Err(_e) => {
                // If we can't get an address, try to get the value from its ap/fp tracking in the
                // hint reference.
                let Some(maybe_relocatable) =
                    get_maybe_relocatable_from_reference(vm, reference, ap_tracking)
                else {
                    // If this fails, it means we're trying an ap-based access on a `let` variable,
                    // whose tracking has been lost due to an unknown ap-change function call.
                    // We have no other choice but to skip these variables.
                    continue;
                };
                match maybe_relocatable {
                    MaybeRelocatable::RelocatableValue(rel) => rel,
                    MaybeRelocatable::Int(felt) => {
                        if cairo_type.as_str() == "felt" {
                            py_ids_dict.borrow_mut(py).items.insert(
                                name.clone(),
                                felt.to_biguint().into_bound_py_any(py)?.into(),
                            );
                            continue;
                        } else {
                            // This means we're accessing a non-felt type (e.g. struct) but it's a
                            // felt value Typically, Evm(cast([ap-2]),
                            // EvmStruct*) would be the case as memory[ap-2] = evm.pc = 0
                            // We return `ap-2` as the address to be used in the `PyVmConst` object
                            //TODO: We can't get this data for now, this is probably a bug in cairo-vm, see <https://github.com/lambdaclass/cairo-vm/issues/1998>
                            continue;
                        }
                    }
                }
            }
        };
        // Some variables don't have values yet; e.g.
        // ```
        // tempvar x: U256
        // %{ my_hint }
        // ```
        let value = vm.get_maybe(&var_addr);

        // Based on the cairo_type and value, return different Python objects
        // to match the original Python VmConsts behavior.
        match cairo_type.as_str() {
            "felt" => match value {
                Some(MaybeRelocatable::Int(felt)) => {
                    // Convert to python int
                    py_ids_dict
                        .borrow_mut(py)
                        .items
                        .insert(name.clone(), felt.to_biguint().into_bound_py_any(py)?.into());
                }
                Some(MaybeRelocatable::RelocatableValue(rel)) => {
                    // Convert to PyRelocatable
                    let py_rel = PyRelocatable { inner: rel };
                    py_ids_dict
                        .borrow_mut(py)
                        .items
                        .insert(name.clone(), Py::new(py, py_rel)?.into_bound_py_any(py)?.into());
                }
                None => {
                    // Create a CairoVar with no value
                    let var = CairoVar {
                        name: name.clone(),
                        value: None,
                        address: Some(var_addr),
                        var_type: CairoVarType::Felt,
                    };
                    let py_var = PyVmConst {
                        var,
                        vm: vm as *mut VirtualMachine,
                        identifiers: Some(identifiers as *const HashMap<String, Identifier>),
                    };
                    py_ids_dict
                        .borrow_mut(py)
                        .items
                        .insert(name.clone(), Py::new(py, py_var)?.into_bound_py_any(py)?.into());
                }
            },
            t if t.ends_with('*') => {
                // Pointer types
                let address =
                    get_ptr_from_var_name(name, vm, ids_data, ap_tracking).unwrap_or(var_addr);
                let var_type = create_var_type(t, identifiers)?;
                if t == "felt*" {
                    // Case 2.1: The pointer is to a felt type
                    match value {
                        Some(MaybeRelocatable::RelocatableValue(rel)) => {
                            let py_rel = PyRelocatable { inner: rel };
                            py_ids_dict.borrow_mut(py).items.insert(
                                name.clone(),
                                Py::new(py, py_rel)?.into_bound_py_any(py)?.into(),
                            );
                        }
                        None => {
                            // Create a CairoVar with no value
                            let var = CairoVar {
                                name: name.clone(),
                                value: None,
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
                            py_ids_dict
                                .borrow_mut(py)
                                .set_item(name, Py::new(py, py_var)?.into_bound_py_any(py)?.into());
                        }
                        _ => {
                            let var = CairoVar {
                                name: name.clone(),
                                value,
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
                            py_ids_dict
                                .borrow_mut(py)
                                .set_item(name, Py::new(py, py_var)?.into_bound_py_any(py)?.into());
                        }
                    }
                } else {
                    // Case 2.2: The pointer is to a non-felt type
                    let var =
                        CairoVar { name: name.clone(), value, address: Some(address), var_type };
                    let py_var = PyVmConst {
                        var,
                        vm: vm as *mut VirtualMachine,
                        identifiers: Some(identifiers as *const HashMap<String, Identifier>),
                    };
                    py_ids_dict
                        .borrow_mut(py)
                        .set_item(name, Py::new(py, py_var)?.into_bound_py_any(py)?.into());
                }
            }
            // Case 3: The variable is a struct. In that case we return a PyVmConst
            // that will load the struct members lazily when the variable is accessed.
            _ => {
                let var_type = create_var_type(cairo_type, identifiers)?;
                let var = CairoVar { name: name.clone(), value, address: Some(var_addr), var_type };
                let py_var = PyVmConst {
                    var,
                    vm: vm as *mut VirtualMachine,
                    identifiers: Some(identifiers as *const HashMap<String, Identifier>),
                };
                py_ids_dict
                    .borrow_mut(py)
                    .set_item(name, Py::new(py, py_var)?.into_bound_py_any(py)?.into());
            }
        }
    }

    Ok(py_ids_dict)
}
