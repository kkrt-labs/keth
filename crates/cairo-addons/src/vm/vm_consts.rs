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
    Felt252,
};
use pyo3::{
    prelude::*,
    types::{PyDict, PyList, PyType},
    IntoPyObjectExt,
};

use super::{dynamic_hint::DynamicHintError, relocatable::PyRelocatable};

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
        /// Member names mapped to their offsets and types
        members: HashMap<String, Member>,
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

/// Extracts struct information from identifiers and returns member details
fn get_struct_info_from_identifiers(
    identifiers: &HashMap<String, Identifier>,
    type_name: &str,
) -> Option<(HashMap<String, Member>, usize)> {
    // For pointer types, strip the trailing asterisks to get the base type
    let base_type_name = type_name.trim_end_matches('*');

    // Look up the struct definition in identifiers
    let identifier = identifiers.get(base_type_name)?;

    // Get the members map if it exists
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
) -> CairoVarType {
    if type_name == "felt" {
        return CairoVarType::Felt(Felt252::from(0));
    }

    // Handle pointer types
    if type_name.ends_with('*') {
        let base_type = type_name.trim_end_matches('*');
        let asterisks_count = type_name.len() - base_type.len();

        // Create the innermost type
        let mut inner_type = if base_type == "felt" {
            CairoVarType::Felt(Felt252::from(0))
        } else {
            // For struct pointers, create a struct type
            CairoVarType::Struct {
                name: base_type.to_string(),
                members: HashMap::new(), // Empty, will be lazy loaded
                size: 1,                 // Default size
            }
        };

        // Add pointer layers
        for _ in 0..asterisks_count {
            inner_type = CairoVarType::Pointer {
                pointee: Box::new(inner_type),
                is_reference: true,
            };
        }

        return inner_type;
    }

    // It's a struct
    CairoVarType::Struct {
        name: type_name.to_string(),
        members: HashMap::new(), // Empty, will be lazy loaded
        size: 1,                 // Default size
    }
}

/// Python-accessible wrapper for Cairo variables that provides a behavior similar to
/// the original Python VmConsts implementation
#[pyclass(name = "VmConst", unsendable)]
pub struct PyVmConst {
    /// The variable information
    pub(crate) var: CairoVar,
    /// Reference to the VM
    pub(crate) vm: *mut VirtualMachine,
    /// Reference to program identifiers for struct member resolution
    pub(crate) identifiers: Option<*const HashMap<String, Identifier>>,
}

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
                    if let Some((new_members, new_size)) = get_struct_info_from_identifiers(identifiers, name) {
                        return CairoVarType::Struct {
                            name: name.clone(),
                            members: new_members,
                            size: new_size,
                        };
                    }
                }
                // Return the original if we couldn't load members
                CairoVarType::Struct {
                    name: name.clone(),
                    members: members.clone(),
                    size: *size,
                }
            }
            CairoVarType::Pointer { pointee, is_reference } => {
                // If it's a pointer to a struct, try to load the struct members
                let new_pointee = Box::new(self.load_struct_members(pointee));
                CairoVarType::Pointer {
                    pointee: new_pointee,
                    is_reference: *is_reference,
                }
            }
            // For other types, just return a clone
            _ => var_type.clone(),
        }
    }

    /// Create a PyVmConst for a member of a struct
    fn create_member_var(&self,
        parent_name: &str,
        member_name: &str,
        member: &Member,
        member_addr: Relocatable
    ) -> PyResult<PyObject> {
        Python::with_gil(|py| {
            let vm = unsafe { &mut *self.vm };

            // Try to get the value from memory
            if let Some(value) = vm.get_maybe(&member_addr) {
                // Get member type from the member definition
                let member_type = create_var_type(member.cairo_type.as_ref(), unsafe { &*self.identifiers.unwrap() });

                // Based on the type, return different Python objects
                match &member_type {
                    CairoVarType::Felt(_) => {
                        // For felt types, return a Python int directly
                        match &value {
                            MaybeRelocatable::Int(felt) => {
                                Ok(felt.to_biguint().into_bound_py_any(py)?.into())
                            }
                            MaybeRelocatable::RelocatableValue(rel) => {
                                // If it's a relocatable but type is felt, still return the relocatable
                                let py_rel = PyRelocatable { inner: *rel };
                                Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into())
                            }
                        }
                    }
                    CairoVarType::Relocatable(_) => {
                        // For relocatable types, return a PyRelocatable directly
                        match &value {
                            MaybeRelocatable::RelocatableValue(rel) => {
                                let py_rel = PyRelocatable { inner: *rel };
                                Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into())
                            }
                            _ => {
                                // Unexpected case, fall back to PyVmConst
                                let var = CairoVar {
                                    name: format!("{}.{}", parent_name, member_name),
                                    value,
                                    address: Some(member_addr),
                                    var_type: member_type,
                                };
                                let py_member = PyVmConst {
                                    var,
                                    vm: self.vm,
                                    identifiers: self.identifiers,
                                };
                                Ok(Py::new(py, py_member)?.into_bound_py_any(py)?.into())
                            }
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
                        let py_member = PyVmConst {
                            var,
                            vm: self.vm,
                            identifiers: self.identifiers,
                        };
                        Ok(Py::new(py, py_member)?.into_bound_py_any(py)?.into())
                    }
                }
            } else {
                Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                    format!("Member '{}' not found in memory", member_name)
                ))
            }
        })
    }

    /// Get value as Python object - convenience method
    pub fn value(&self, py: Python<'_>) -> PyResult<PyObject> {
        match &self.var.value {
            MaybeRelocatable::Int(felt) => {
                Ok(felt.to_biguint().into_bound_py_any(py)?.into())
            }
            MaybeRelocatable::RelocatableValue(rel) => {
                let py_rel = PyRelocatable { inner: *rel };
                Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into())
            }
        }
    }

    /// Helper method to chain struct member access with lazy loading support
    /// This can be used in Python to access nested struct members like: x.chain_attr("a.b.c")
    pub fn chain_attr(&self, path: &str, py: Python<'_>) -> PyResult<PyObject> {
        let parts: Vec<&str> = path.split('.').collect();
        if parts.is_empty() {
            return Err(PyErr::new::<pyo3::exceptions::PyValueError, _>(
                "Empty path provided for chain_attr"
            ));
        }

        // Start with self
        let mut current_obj = self.__getattr__(parts[0], py)?;

        // Access each part in sequence
        for part in parts.iter().skip(1) {
            if let Ok(next) = current_obj.call_method1(py, "__getattr__", (part,)) {
                current_obj = next;
            } else {
                return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                    "Failed to access '{}' in chain {}",
                    part, path
                )));
            }
        }

        Ok(current_obj)
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

        // Create a possibly updated var_type with lazily loaded members
        let var_type = self.load_struct_members(&self.var.var_type);

        // Handle different types
        match &var_type {
            CairoVarType::Struct { members, size, .. } => {
                // Check if the member exists
                if let Some(member) = members.get(name) {
                    // For structs, get the member by adding the offset to the address
                    if let Some(addr) = self.var.address {
                        // Extract offset as a numeric value we can use for address calculation
                        let offset_value = member.offset as usize;
                        let member_addr = (addr + offset_value).map_err(|e| {
                            PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                        })?;

                        // Check if the member is a felt* and return a PyRelocatable directly
                        if member.cairo_type.as_str() == "felt*" {
                            let vm = unsafe { &mut *self.vm };
                            if let Some(value) = vm.get_maybe(&member_addr) {
                                if let MaybeRelocatable::RelocatableValue(rel) = value {
                                    let py_rel = PyRelocatable { inner: rel };
                                    return Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into());
                                }
                            }
                        }

                        return self.create_member_var(&self.var.name, name, member, member_addr);
                    } else {
                        return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                            "Struct does not have an address",
                        ));
                    }
                } else if name == "SIZE" {
                    // Special case for SIZE member
                    return Ok(size.into_bound_py_any(py)?.into());
                } else {
                    return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                        "'{}' is not a member of struct",
                        name
                    )));
                }
            }
            CairoVarType::Pointer { pointee, .. } => {
                // If it's a pointer to a struct, we need to access the struct members directly
                if let CairoVarType::Struct { members, .. } = pointee.as_ref() {
                    // Check if the member exists in the struct
                    if let Some(member) = members.get(name) {
                        // For pointers, we need to:
                        // 1. Get the address the pointer points to
                        let vm = unsafe { &mut *self.vm };
                        if let Some(ptr_addr) = self.var.address {
                            // 2. Calculate the member address by adding the offset to the pointer value
                            let offset_value = member.offset as usize;
                            let member_addr = (ptr_addr + offset_value).map_err(|e| {
                                PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                            })?;

                            // Check if the member is a felt* and return a PyRelocatable directly
                            if member.cairo_type.as_str() == "felt*" {
                                if let Some(value) = vm.get_maybe(&member_addr) {
                                    if let MaybeRelocatable::RelocatableValue(rel) = value {
                                        let py_rel = PyRelocatable { inner: rel };
                                        return Ok(Py::new(py, py_rel)?.into_bound_py_any(py)?.into());
                                    }
                                }
                            }

                            // 3. Create a member variable at that address
                            return self.create_member_var(&format!("(*{})", self.var.name), name, member, member_addr);
                        } else {
                            return Err(PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(
                                "Pointer value is not a relocatable address"
                            ));
                        }
                    } else {
                        return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                            "'{}' is not a member of the struct pointed to by '{}'",
                            name, self.var.name
                        )));
                    }
                } else {
                    return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                        "'{}' is not a pointer to a struct",
                        self.var.name
                    )));
                }
            }
            _ => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                "'{}' has no attribute '{}'",
                self.var.name, name
            ))),
        }
    }

    /// Get an item by index if this is an array
    pub fn __getitem__(&self, idx: usize, py: Python<'_>) -> PyResult<PyObject> {
        // Create a possibly updated var_type with lazily loaded members
        let var_type = self.load_struct_members(&self.var.var_type);

        // Handle array access, treating structs as arrays
        match &var_type {
            CairoVarType::Struct { size, .. } => {
                if let Some(addr) = self.var.address {
                    let vm = unsafe { &mut *self.vm };
                    let item_addr = (addr + (idx * size)).map_err(|e| {
                        PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                    })?;

                    // Create a new CairoVar for the array item with the same type
                    let item_var = CairoVar {
                        name: format!("{}[{}]", self.var.name, idx),
                        // Try to get the actual value
                        value: vm.get_maybe(&item_addr).unwrap_or(MaybeRelocatable::RelocatableValue(item_addr)),
                        address: Some(item_addr),
                        // Use the same type for array elements
                        var_type: var_type.clone(),
                    };

                    let py_item = PyVmConst {
                        var: item_var,
                        vm: self.vm,
                        identifiers: self.identifiers,
                    };
                    return Ok(Py::new(py, py_item)?.into_bound_py_any(py)?.into());
                } else {
                    return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                        "Cannot index a variable without an address",
                    ));
                }
            }
            CairoVarType::Pointer { pointee, .. } => {
                // If it's a pointer, dereference it and then index
                if let Ok(deref_obj) = self.deref(py) {
                    // Then access the indexed item on the dereferenced object
                    if let Ok(item) = deref_obj.call_method1(py, "__getitem__", (idx,)) {
                        return Ok(item);
                    }
                }
                return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                    "Cannot index this pointer",
                ));
            }
            _ => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                "'{}' object is not subscriptable",
                self.var.name
            ))),
        }
    }

    /// Set the value of the variable
    pub fn __setattr__(
        &self,
        name: &str,
        value: &Bound<'_, PyAny>,
        py: Python<'_>,
    ) -> PyResult<()> {
        // Don't allow setting special attributes
        if name == "address_" {
            return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                "Cannot modify address_ attribute",
            ));
        }

        // Create a possibly updated var_type with lazily loaded members
        let var_type = self.load_struct_members(&self.var.var_type);

        // Handle struct member assignment
        match &var_type {
            CairoVarType::Struct { members, .. } => {
                if let Some(member) = members.get(name) {
                    let offset_value = member.offset as usize;
                    if let Some(addr) = self.var.address {
                        let vm = unsafe { &mut *self.vm };
                        let member_addr = (addr + offset_value).map_err(|e| {
                            PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                        })?;

                        // Convert Python value to MaybeRelocatable
                        let rust_value = if let Ok(num) = value.extract::<u64>() {
                            MaybeRelocatable::Int(Felt252::from(num))
                        } else if let Ok(relocatable) = value.extract::<PyRelocatable>() {
                            MaybeRelocatable::RelocatableValue(relocatable.inner)
                        } else {
                            return Err(PyErr::new::<pyo3::exceptions::PyTypeError, _>(
                                "Value must be a number or a Relocatable",
                            ));
                        };

                        // Set the value in memory
                        vm.insert_value(member_addr, rust_value).map_err(|e| {
                            PyErr::new::<pyo3::exceptions::PyRuntimeError, _>(e.to_string())
                        })?;

                        return Ok(());
                    } else {
                        return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(
                            "Struct does not have an address",
                        ));
                    }
                } else {
                    return Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                        "'{}' is not a member of struct",
                        name
                    )));
                }
            }
            _ => Err(PyErr::new::<pyo3::exceptions::PyAttributeError, _>(format!(
                "'{}' object has no attribute '{}'",
                self.var.name, name
            ))),
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
            CairoVarType::Pointer { pointee, .. } => match &**pointee {
                CairoVarType::Felt(_) => "felt*".to_string(),
                CairoVarType::Relocatable(_) => "relocatable*".to_string(),
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

                    let py_deref = PyVmConst {
                        var: deref_var,
                        vm: self.vm,
                        identifiers: self.identifiers,
                    };
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
#[pyclass(name = "VmConstsDict", unsendable)]
pub struct PyVmConstsDict {
    /// Map of variable names to Python objects
    pub(crate) items: HashMap<String, Py<PyAny>>,
    /// Reference to the VM
    pub(crate) vm: *mut VirtualMachine,
    /// Reference to program identifiers for struct member resolution
    pub(crate) identifiers: Option<*const HashMap<String, Identifier>>,
}

impl PyVmConstsDict {
    /// Create a new empty PyVmConstsDict
    pub fn new() -> Self {
        Self {
            items: HashMap::new(),
            vm: std::ptr::null_mut(),
            identifiers: None,
        }
    }

    /// Configure the VM reference
    pub fn configure(&mut self, vm: *mut VirtualMachine, identifiers: Option<*const HashMap<String, Identifier>>) {
        self.vm = vm;
        self.identifiers = identifiers;
    }
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

/// Creates a VmConstsDict from IDs data and VM
pub fn create_vm_consts_dict(
    vm: &mut VirtualMachine,
    identifiers: &HashMap<String, Identifier>,
    ids_data: &HashMap<String, HintReference>,
    ap_tracking: &ApTracking,
    py: Python<'_>,
) -> Result<Py<PyVmConstsDict>, DynamicHintError> {
    let mut ids_dict = PyVmConstsDict::new();
    ids_dict.configure(vm as *mut VirtualMachine, Some(identifiers as *const HashMap<String, Identifier>));

    let py_ids_dict = Py::new(py, ids_dict)?;

    // Extract variables from ids_data
    for (name, reference) in ids_data {
        let cairo_type = reference.cairo_type.clone();

        // Get the address and value using the existing hint_utils functions
        if let Ok(var_addr) = get_relocatable_from_var_name(name, vm, ids_data, ap_tracking) {
            if let Some(value) = vm.get_maybe(&var_addr) {
                // Based on the cairo_type and value, return different Python objects
                // to match the original Python VmConsts behavior

                // Add to dictionary based on type
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
                        // It's a pointer
                        let address =
                            get_ptr_from_var_name(name, vm, ids_data, ap_tracking).unwrap_or(var_addr);

                        // Create a CairoVarType based on the type_str
                        let var_type = create_var_type(type_str, identifiers);

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
                                        identifiers: Some(identifiers as *const HashMap<String, Identifier>),
                                    };
                                    let py_var_obj =
                                        Py::new(py, py_var)?.into_bound_py_any(py)?.into();
                                    py_ids_dict.borrow_mut(py).set_item(name, py_var_obj);
                                }
                            }
                        } else {
                            // Pointer to a non-felt type - use PyVmConst
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
                        // It's a struct - use PyVmConst
                        let address =
                            get_ptr_from_var_name(name, vm, ids_data, ap_tracking).unwrap_or(var_addr);

                        // Create a CairoVarType based on the type_str
                        let var_type = create_var_type(type_str, identifiers);

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
                    // No type information, infer from value
                    match &value {
                        MaybeRelocatable::Int(felt) => {
                            // Convert to Python int
                            let py_int = felt.to_biguint().into_bound_py_any(py)?.into();
                            py_ids_dict.borrow_mut(py).items.insert(name.clone(), py_int);
                        }
                        MaybeRelocatable::RelocatableValue(rel) => {
                            // Return PyRelocatable directly
                            let py_rel = PyRelocatable { inner: *rel };
                            let py_rel_obj = Py::new(py, py_rel)?.into_bound_py_any(py)?.into();
                            py_ids_dict.borrow_mut(py).items.insert(name.clone(), py_rel_obj);
                        }
                    }
                }
            }
        }
    }

    Ok(py_ids_dict)
}
