use std::collections::HashMap;
use std::fmt;

use cairo_vm::{
    hint_processor::{builtin_hint_processor::hint_utils::{get_ptr_from_var_name, get_relocatable_from_var_name}, hint_processor_definition::HintReference},
    serde::deserialize_program::ApTracking,
    types::relocatable::{MaybeRelocatable, Relocatable},
    vm::vm_core::VirtualMachine,
    Felt252,
};
use pyo3::{prelude::*, types::{PyDict, PyList}, IntoPyObjectExt};

use super::{
    dynamic_hint::DynamicHintError,
    memory_segments::PyMemoryWrapper,
    relocatable::PyRelocatable,
};

/// Represents the different types of Cairo variables that can be accessed
#[derive(Debug, Clone)]
pub enum CairoVarType {
    /// A basic Cairo felt value
    Felt(Felt252),
    /// A relocatable value (memory address)
    Relocatable(Relocatable),
    /// A struct that has members
    Struct {
        /// The name of the struct
        name: String,
        /// Member names mapped to their offsets
        members: HashMap<String, usize>,
        /// The total size of the struct
        size: usize,
    },
    /// A pointer to another type
    Pointer {
        /// The type being pointed to
        pointee: Box<CairoVarType>,
        /// Whether this is a reference (T*) or a pointer (T**)
        is_reference: bool,
    },
}

/// Holds information about a Cairo variable's name, value, and address
#[derive(Debug, Clone)]
pub struct CairoVar {
    /// The name of the variable
    pub name: String,
    /// The value of the variable
    pub value: MaybeRelocatable,
    /// The address of the variable in memory
    pub address: Option<Relocatable>,
    /// The type of the variable
    pub var_type: CairoVarType,
}

/// Python-accessible wrapper for Cairo variables that provides a behavior similar to
/// the original Python VmConsts implementation
#[pyclass(name = "VmConst", unsendable)]
pub struct PyVmConst {
    /// The variable information
    pub(crate) var: CairoVar,
    /// Reference to the VM
    pub(crate) vm: *mut VirtualMachine,
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
            None => {
                Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                    "This variable does not have an address"
                ))
            }
        }
    }

    /// Get the value of the variable
    #[getter]
    pub fn value(&self, py: Python<'_>) -> PyResult<PyObject> {
        match &self.var.value {
            MaybeRelocatable::Int(felt) => {
                let num = felt.to_biguint();
                Ok(num.into_bound_py_any(py)?.into())
            }
            MaybeRelocatable::RelocatableValue(rel) => {
                // If this is a pointer type, try to also provide the value it points to
                if let CairoVarType::Pointer { .. } = &self.var.var_type {
                    // Try to read the value at the pointer location
                    let vm = unsafe { &mut *self.vm };
                    if let Some(pointed_value) = vm.get_maybe(rel) {
                        // Return a dict with both the pointer and the value
                        let result = PyDict::new(py);

                        // Add the pointer
                        let py_rel = PyRelocatable { inner: *rel };
                        result.set_item("ptr", Py::new(py, py_rel)?)?;

                        // Add the dereferenced value
                        match &pointed_value {
                            MaybeRelocatable::Int(felt) => {
                                result.set_item("val", felt.to_biguint())?;
                            }
                            MaybeRelocatable::RelocatableValue(inner_rel) => {
                                let inner_py_rel = PyRelocatable { inner: *inner_rel };
                                result.set_item("val", Py::new(py, inner_py_rel)?)?;
                            }
                        }

                        return Ok(result.into());
                    }
                }

                // Fall back to just returning the relocatable
                let py_rel = PyRelocatable { inner: *rel };
                Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into())
            }
        }
    }

    /// Get a member of the variable if it's a struct
    pub fn __getattr__(&self, name: &str, py: Python<'_>) -> PyResult<PyObject> {
        if name == "address_" {
            return self.address_(py);
        }

        if name == "val" || name == "v" {
            return self.value(py);
        }

        // Handle different types
        match &self.var.var_type {
            CairoVarType::Struct { members, .. } => {
                // Check if the member exists
                if let Some(&offset) = members.get(name) {
                    // For structs, get the member by adding the offset to the address
                    if let Some(addr) = self.var.address {
                        let vm = unsafe { &mut *self.vm };
                        let member_addr = (addr + offset).map_err(|e| {
                            PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                        })?;

                        // Try to get the value from memory
                        if let Some(value) = vm.get_maybe(&member_addr) {
                            // Create a new CairoVar for the member
                            let member_var = CairoVar {
                                name: format!("{}.{}", self.var.name, name),
                                value,
                                address: Some(member_addr),
                                // For simplicity, treat all members as felts for now
                                var_type: CairoVarType::Felt(Felt252::from(0)),
                            };

                            let py_member = PyVmConst { var: member_var, vm: self.vm };
                            Ok(Py::new(py, py_member)?.into_bound_py_any(py)?.into())
                        } else {
                            Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                                format!("Member '{}' not found in memory", name)
                            ))
                        }
                    } else {
                        Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                            "Struct does not have an address"
                        ))
                    }
                } else if name == "SIZE" {
                    // Special case for SIZE member
                    if let CairoVarType::Struct { size, .. } = &self.var.var_type {
                        Ok(size.into_bound_py_any(py)?.into())
                    } else {
                        Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                            "SIZE is only available for struct types"
                        ))
                    }
                } else {
                    Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                        format!("'{}' is not a member of struct", name)
                    ))
                }
            }
            CairoVarType::Pointer { pointee, .. } => {
                // If it's a pointer to a struct, forward the attribute access to the struct
                match &**pointee {
                    CairoVarType::Struct { .. } => {
                        // Get the value the pointer points to
                        if let MaybeRelocatable::RelocatableValue(rel) = self.var.value {
                            let vm = unsafe { &mut *self.vm };

                            // Try to get the struct member
                            if let Ok(struct_addr) = vm.get_relocatable(rel) {
                                match pointee.as_ref() {
                                    CairoVarType::Struct { members, .. } => {
                                        if let Some(&offset) = members.get(name) {
                                            let member_addr = (struct_addr + offset).map_err(|e| {
                                                PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                                            })?;

                                            if let Some(value) = vm.get_maybe(&member_addr) {
                                                // Create a new CairoVar for the member
                                                let member_var = CairoVar {
                                                    name: format!("(*{}).{}", self.var.name, name),
                                                    value,
                                                    address: Some(member_addr),
                                                    var_type: CairoVarType::Felt(Felt252::from(0)),
                                                };

                                                let py_member = PyVmConst { var: member_var, vm: self.vm };
                                                return Ok(Py::new(py, py_member)?.into_bound_py_any(py)?.into());
                                            }
                                        }
                                    }
                                    _ => {}
                                }
                            }
                        }
                        Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                            format!("Unable to access member '{}' through pointer", name)
                        ))
                    }
                    _ => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                        format!("'{}' is not a member pointer does not point to a struct", name)
                    )),
                }
            }
            _ => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                format!("'{}' has no attribute '{}'", self.var.name, name)
            )),
        }
    }

    /// Get an item by index if this is an array
    pub fn __getitem__(&self, idx: usize, py: Python<'_>) -> PyResult<PyObject> {
        // Handle array access, treating structs as arrays
        match &self.var.var_type {
            CairoVarType::Struct { size, .. } => {
                if let Some(addr) = self.var.address {
                    let vm = unsafe { &mut *self.vm };
                    let item_addr = (addr + (idx * size)).map_err(|e| {
                        PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                    })?;

                    // Create a new CairoVar for the array item
                    let item_var = CairoVar {
                        name: format!("{}[{}]", self.var.name, idx),
                        // For simplicity, we don't pre-fetch the value
                        value: MaybeRelocatable::RelocatableValue(item_addr),
                        address: Some(item_addr),
                        // Copy the type
                        var_type: self.var.var_type.clone(),
                    };

                    let py_item = PyVmConst { var: item_var, vm: self.vm };
                    Ok(Py::new(py, py_item)?.into_bound_py_any(py)?.into())
                } else {
                    Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                        "Cannot index a variable without an address"
                    ))
                }
            }
            CairoVarType::Pointer { pointee, .. } => {
                // If it's a pointer, dereference it and then index
                if let MaybeRelocatable::RelocatableValue(ptr) = self.var.value {
                    match pointee.as_ref() {
                        CairoVarType::Struct { size, .. } => {
                            // Calculate array offset
                            let item_addr = (ptr + (idx * size)).map_err(|e| {
                                PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                            })?;

                            // Create a new CairoVar for the array item
                            let item_var = CairoVar {
                                name: format!("(*{})[{}]", self.var.name, idx),
                                value: MaybeRelocatable::RelocatableValue(item_addr),
                                address: Some(item_addr),
                                var_type: (**pointee).clone(),
                            };

                            let py_item = PyVmConst { var: item_var, vm: self.vm };
                            Ok(Py::new(py, py_item)?.into_bound_py_any(py)?.into())
                        }
                        _ => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                            "Cannot index a pointer to a non-struct type"
                        )),
                    }
                } else {
                    Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                        "Cannot index a non-pointer value"
                    ))
                }
            }
            _ => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                format!("'{}' object is not subscriptable", self.var.name)
            )),
        }
    }

    /// Set the value of the variable
    pub fn __setattr__(&self, name: &str, value: &Bound<'_, PyAny>, py: Python<'_>) -> PyResult<()> {
        // Don't allow setting special attributes
        if name == "address_" {
            return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                "Cannot modify address_ attribute"
            ));
        }

        // Handle struct member assignment
        match &self.var.var_type {
            CairoVarType::Struct { members, .. } => {
                if let Some(&offset) = members.get(name) {
                    if let Some(addr) = self.var.address {
                        let vm = unsafe { &mut *self.vm };
                        let member_addr = (addr + offset).map_err(|e| {
                            PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                        })?;

                        // Convert Python value to MaybeRelocatable
                        let rust_value = if let Ok(num) = value.extract::<u64>() {
                            MaybeRelocatable::Int(Felt252::from(num))
                        } else if let Ok(relocatable) = value.extract::<PyRelocatable>() {
                            MaybeRelocatable::RelocatableValue(relocatable.inner)
                        } else {
                            return Err(PyErr::new::<pyo3::exceptions::PyTypeError, _>(
                                "Value must be a number or a Relocatable"
                            ));
                        };

                        // Set the value in memory
                        vm.insert_value(member_addr, rust_value).map_err(|e| {
                            PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                        })?;

                        Ok(())
                    } else {
                        Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                            "Struct does not have an address"
                        ))
                    }
                } else {
                    Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                        format!("'{}' is not a member of struct", name)
                    ))
                }
            }
            _ => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                format!("'{}' object has no attribute '{}'", self.var.name, name)
            )),
        }
    }

    /// Returns true if this variable is a pointer
    #[getter]
    pub fn is_pointer(&self) -> bool {
        matches!(self.var.var_type, CairoVarType::Pointer { .. })
    }

    /// Returns true if this variable is a struct
    #[getter]
    pub fn is_struct(&self) -> bool {
        matches!(self.var.var_type, CairoVarType::Struct { .. })
    }

    /// Get the type name of the variable
    #[getter]
    pub fn type_name(&self) -> String {
        match &self.var.var_type {
            CairoVarType::Felt(_) => "felt".to_string(),
            CairoVarType::Relocatable(_) => "relocatable".to_string(),
            CairoVarType::Struct { name, .. } => name.clone(),
            CairoVarType::Pointer { pointee, .. } => {
                match &**pointee {
                    CairoVarType::Felt(_) => "felt*".to_string(),
                    CairoVarType::Relocatable(_) => "relocatable*".to_string(),
                    CairoVarType::Struct { name, .. } => format!("{}*", name),
                    CairoVarType::Pointer { .. } => "pointer*".to_string(),
                }
            }
        }
    }

    /// String representation
    pub fn __str__(&self) -> String {
        match &self.var.var_type {
            CairoVarType::Struct { name, .. } => {
                format!("{}({})", name, self.var.name)
            }
            CairoVarType::Pointer { pointee, .. } => {
                match &**pointee {
                    CairoVarType::Struct { name, .. } => {
                        format!("{}*({})", name, self.var.name)
                    }
                    _ => match &self.var.value {
                        MaybeRelocatable::Int(felt) => format!("{}", felt),
                        MaybeRelocatable::RelocatableValue(rel) => format!("{}", rel),
                    },
                }
            }
            _ => match &self.var.value {
                MaybeRelocatable::Int(felt) => format!("{}", felt),
                MaybeRelocatable::RelocatableValue(rel) => format!("{}", rel),
            },
        }
    }

    /// Repr string
    pub fn __repr__(&self) -> String {
        format!("VmConst(name='{}', type={}, value={}, address={:?})",
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

                    let py_deref = PyVmConst { var: deref_var, vm: self.vm };
                    return Ok(Py::new(py, py_deref)?.into_bound_py_any(py)?.into());
                } else {
                    return Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(
                        format!("Could not dereference pointer: no value at address {}", rel)
                    ));
                }
            }
        }

        Err(PyErr::new::<pyo3::exceptions::PyTypeError, _>(
            format!("Cannot dereference non-pointer value: {}", self.var.name)
        ))
    }
}

/// A dictionary that stores Cairo variables and allows access by name
#[pyclass(name = "VmConstsDict", unsendable)]
pub struct PyVmConstsDict {
    /// Map of variable names to VmConst objects
    items: HashMap<String, Py<PyVmConst>>,
    /// Reference to the VM
    vm: *mut VirtualMachine,
}

#[pymethods]
impl PyVmConstsDict {
    /// Get a variable by name
    pub fn __getattr__(&self, name: &str, py: Python<'_>) -> PyResult<PyObject> {
        match self.items.get(name) {
            Some(var) => Ok(var.clone_ref(py).into_bound_py_any(py)?.into()),
            None => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                format!("'VmConstsDict' object has no attribute '{}'", name)
            )),
        }
    }

    /// Get a variable by dictionary access
    pub fn __getitem__(&self, name: &str, py: Python<'_>) -> PyResult<PyObject> {
        self.__getattr__(name, py)
    }

    /// Add or update a variable
    pub fn set_item(&mut self, key: &str, value: Py<PyVmConst>) {
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

/// Creates a VmConstsDict from IDs data and VM
pub fn create_vm_consts_dict(
    vm: &mut VirtualMachine,
    ids_data: &HashMap<String, HintReference>,
    ap_tracking: &ApTracking,
    py: Python<'_>,
) -> Result<Py<PyVmConstsDict>, DynamicHintError> {
    let ids_dict = PyVmConstsDict {
        items: HashMap::new(),
        vm: vm as *mut VirtualMachine,
    };

    let py_ids_dict = Py::new(py, ids_dict)?;

    // Extract variables from ids_data
    for (name, reference) in ids_data {
        let cairo_type = reference.cairo_type.clone();

        // Get the address and value using the existing hint_utils functions
        if let Ok(var_addr) = get_relocatable_from_var_name(
            name, vm, ids_data, ap_tracking
        ) {
            if let Some(value) = vm.get_maybe(&var_addr) {
                // Determine the appropriate CairoVarType based on the cairo_type and value
                let (var_type, address) = if let Some(type_str) = cairo_type {
                    if type_str == "felt" {
                        // It's a felt
                        let address = var_addr.clone();
                        match &value {
                            MaybeRelocatable::Int(felt) => (CairoVarType::Felt(felt.clone()), address),
                            MaybeRelocatable::RelocatableValue(rel) => {
                                // Special case for variables that are relocatable, but their type is `felt`.
                                // This is known to happen for `range_check_ptr` and some internal `_temp` variables.
                                // Perhaps a mistake in the language design...
                                (CairoVarType::Relocatable(rel.clone()), address)
                            }
                        }
                    } else if type_str.ends_with('*') {
                        // It's a pointer
                        let address = get_ptr_from_var_name(name, vm, ids_data, ap_tracking).unwrap();
                        let base_type = type_str.trim_end_matches('*');
                        let (pointee, address) = if base_type == "felt" {
                            // Pointer to a felt
                            (Box::new(CairoVarType::Felt(Felt252::from(0))), address)
                        } else {
                            // Pointer to a struct
                            (Box::new(CairoVarType::Struct {
                                name: base_type.to_string(),
                                members: HashMap::new(), // Empty for now
                                size: 1,                // TODO: Determine struct size properly
                            }), address)
                        };

                        (CairoVarType::Pointer {
                            pointee,
                            is_reference: true,
                        }, address)
                    } else {
                        // It's a struct
                        let address = get_ptr_from_var_name(name, vm, ids_data, ap_tracking).unwrap();
                        (CairoVarType::Struct {
                            name: type_str.to_string(),
                            members: HashMap::new(), // Empty for now
                            size: 1,                // TODO: Determine struct size properly
                        }, address)
                    }
                } else {
                    // No type information, infer from value
                    match &value {
                        MaybeRelocatable::Int(felt) => {
                            let address = var_addr.clone();
                            (CairoVarType::Felt(felt.clone()), address)
                        },
                        MaybeRelocatable::RelocatableValue(_) => {
                            let address = get_ptr_from_var_name(name, vm, ids_data, ap_tracking).unwrap();
                            // Default to pointer to felt if we don't know the type
                            (CairoVarType::Pointer {
                                pointee: Box::new(CairoVarType::Felt(Felt252::from(0))),
                                is_reference: true,
                            }, address)
                        }
                    }
                };

                // Create a variable with the appropriate type
                let var = CairoVar {
                    name: name.clone(),
                    value,
                    address: Some(address),
                    var_type,
                };

                // Create a PyVmConst for this variable
                let py_var = PyVmConst { var, vm: vm as *mut VirtualMachine };
                let py_var_obj = Py::new(py, py_var)?;

                // Add to the dictionary
                py_ids_dict.borrow_mut(py).set_item(name, py_var_obj);
            }
        }
    }

    Ok(py_ids_dict)
}
