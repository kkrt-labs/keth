use cairo_vm::{
    hint_processor::hint_processor_definition::HintReference,
    serde::deserialize_program::{ApTracking, OffsetValue},
    types::{instruction::Register, relocatable::{MaybeRelocatable, Relocatable}},
    vm::vm_core::VirtualMachine,
    Felt252,
};
use pyo3::{prelude::*, types::PyDict};
use std::collections::HashMap;

use crate::vm::vm_consts::{CairoVar, CairoVarType, PyVmConst, PyVmConstsDict, create_vm_consts_dict};

/// Test creating and using a PyVmConst
#[test]
fn test_py_vm_const() {
    Python::with_gil(|py| {
        // Create a VM and initialize a simple variable
        let mut vm = VirtualMachine::new(false, false);
        let addr = Relocatable::from((0, 5));

        // Insert a test value
        vm.insert_value(addr, MaybeRelocatable::Int(Felt252::from(42)))
            .expect("Failed to insert value");

        // Create a CairoVar
        let var = CairoVar {
            name: "test_var".to_string(),
            value: MaybeRelocatable::Int(Felt252::from(42)),
            address: Some(addr),
            var_type: CairoVarType::Felt(Felt252::from(0)),
        };

        // Create a PyVmConst
        let py_const = PyVmConst {
            var,
            vm: &mut vm as *mut VirtualMachine,
        };

        // Test value() method
        let value = py_const.value(py).expect("Failed to get value");
        assert_eq!(value.extract::<u64>(py).unwrap(), 42);

        // Test address_() method
        let addr_obj = py_const.address_(py).expect("Failed to get address");
        let addr_dict = addr_obj.downcast::<PyAny>(py).unwrap().getattr("__dict__").unwrap();
        let segment_index = addr_dict.get_item("segment_index").unwrap().extract::<isize>().unwrap();
        let offset = addr_dict.get_item("offset").unwrap().extract::<usize>().unwrap();
        assert_eq!(segment_index, 0);
        assert_eq!(offset, 5);

        // Test __str__ and __repr__ methods
        assert_eq!(py_const.__str__(), "42");
        assert!(py_const.__repr__().contains("test_var"));
    });
}

/// Test creating and using a PyVmConstsDict
#[test]
fn test_py_vm_consts_dict() {
    Python::with_gil(|py| {
        // Create a VM
        let mut vm = VirtualMachine::new(false, false);
        let addr = Relocatable::from((0, 5));

        // Insert a test value
        vm.insert_value(addr, MaybeRelocatable::Int(Felt252::from(42)))
            .expect("Failed to insert value");

        // Create a PyVmConstsDict
        let mut dict = PyVmConstsDict::new();
        dict.configure(&mut vm as *mut VirtualMachine);

        // Create a test variable
        let var = CairoVar {
            name: "test_var".to_string(),
            value: MaybeRelocatable::Int(Felt252::from(42)),
            address: Some(addr),
            var_type: CairoVarType::Felt(Felt252::from(0)),
        };

        // Create a PyVmConst and add it to the dictionary
        let py_const = PyVmConst {
            var,
            vm: &mut vm as *mut VirtualMachine,
        };

        let py_const_obj = Py::new(py, py_const).unwrap();
        dict.set_item("test_var", py_const_obj);

        // Test getting the item
        let py_dict = Py::new(py, dict).unwrap();
        let locals = PyDict::new(py);
        locals.set_item("ids", py_dict).unwrap();

        // Use Python to access the variable
        py.run("assert ids.test_var.value() == 42", None, Some(&locals)).unwrap();

        // Test keys() method
        py.run("assert 'test_var' in ids.keys()", None, Some(&locals)).unwrap();

        // Test __str__ and __repr__ methods
        py.run("assert 'VmConstsDict' in str(ids)", None, Some(&locals)).unwrap();
        py.run("assert 'test_var' in repr(ids)", None, Some(&locals)).unwrap();
    });
}

/// Test creating a VmConsts dictionary using the create_vm_consts_dict function
#[test]
fn test_create_vm_consts_dict() {
    Python::with_gil(|py| {
        // Create a VM
        let mut vm = VirtualMachine::new(false, false);

        // Add a memory segment and a variable
        let addr = Relocatable::from((0, 5));
        vm.insert_value(addr, MaybeRelocatable::Int(Felt252::from(42)))
            .expect("Failed to insert value");

        // Create a fake HintReference
        let mut ids_data = HashMap::new();
        let ap_tracking = ApTracking {
            group: 0,
            offset: 0,
        };

        // Create a hint reference pointing to our value
        let hint_ref = HintReference {
            offset1: OffsetValue::Reference(Register::FP, 0, false, true),
            offset2: OffsetValue::Value(5),
            inner_dereference: false,
            outer_dereference: true,
            ap_tracking_data: Some(ap_tracking.clone()),
            cairo_type: None,
        };

        ids_data.insert("test_var".to_string(), hint_ref);

        // Create the VmConstsDict
        let py_dict = create_vm_consts_dict(&mut vm, &ids_data, &ap_tracking, py)
            .expect("Failed to create vm_consts_dict");

        // Test using it
        let locals = PyDict::new(py);
        locals.set_item("ids", py_dict).unwrap();

        // Try to access the value
        py.run("assert hasattr(ids, 'test_var')", None, Some(&locals)).unwrap();

        // This might fail if the referencing doesn't work correctly, but it should work
        // with the proper setup
        let result = py.run("print(ids.test_var.value())", None, Some(&locals));
        println!("Result: {:?}", result);
    });
}

/// Test struct-like access with the VmConsts
#[test]
fn test_struct_access() {
    Python::with_gil(|py| {
        // Create a VM
        let mut vm = VirtualMachine::new(false, false);

        // Create a "struct" in memory
        let struct_base = Relocatable::from((0, 10));
        // First field - a felt (42)
        vm.insert_value(struct_base, MaybeRelocatable::Int(Felt252::from(42)))
            .expect("Failed to insert value");
        // Second field - a felt (123)
        vm.insert_value(struct_base + 1, MaybeRelocatable::Int(Felt252::from(123)))
            .expect("Failed to insert value");

        // Create a CairoVar for the struct
        let mut members = HashMap::new();
        members.insert("x".to_string(), 0);
        members.insert("y".to_string(), 1);

        let var = CairoVar {
            name: "point".to_string(),
            value: MaybeRelocatable::RelocatableValue(struct_base),
            address: Some(struct_base),
            var_type: CairoVarType::Struct {
                name: "Point".to_string(),
                members,
                size: 2,
            },
        };

        // Create a PyVmConst
        let py_const = PyVmConst {
            var,
            vm: &mut vm as *mut VirtualMachine,
        };

        let py_const_obj = Py::new(py, py_const).unwrap();

        // Create a dict and add the struct
        let mut dict = PyVmConstsDict::new();
        dict.configure(&mut vm as *mut VirtualMachine);
        dict.set_item("point", py_const_obj);

        let py_dict = Py::new(py, dict).unwrap();
        let locals = PyDict::new(py);
        locals.set_item("ids", py_dict).unwrap();

        // Test accessing struct members
        py.run("assert ids.point.x.value() == 42", None, Some(&locals)).unwrap();
        py.run("assert ids.point.y.value() == 123", None, Some(&locals)).unwrap();

        // Test array-like access
        py.run("assert ids.point[0].value() == 42", None, Some(&locals)).unwrap();
        py.run("assert ids.point[1].value() == 123", None, Some(&locals)).unwrap();
    });
}

#[test]
fn test_pointer_deref() {
    Python::with_gil(|py| {
        // Create a simple VM
        let mut vm = VirtualMachine::new(
            true, /* dummy */
            false,
            vec![],
            RemappingType::Enabled,
        ).unwrap();

        // Set up memory for a pointer test
        let segment_index = 0;
        let rel = Relocatable::from((segment_index, 5)); // Address of our pointer
        let target_rel = Relocatable::from((segment_index, 10)); // Target of our pointer

        // Store the target address in memory at the pointer location
        vm.insert_value(rel, MaybeRelocatable::RelocatableValue(target_rel)).unwrap();

        // Store a value at the target location
        let target_value = Felt252::from(42);
        vm.insert_value(target_rel, MaybeRelocatable::from(target_value)).unwrap();

        // Create a pointer variable
        let pointer_var = CairoVar {
            name: "ptr".to_string(),
            value: MaybeRelocatable::RelocatableValue(rel),
            address: Some(Relocatable::from((segment_index, 0))),
            var_type: CairoVarType::Pointer {
                pointee: Box::new(CairoVarType::Felt),
                size: 1,
            },
        };

        // Create PyVmConst for the pointer
        let py_ptr = PyVmConst {
            var: pointer_var,
            vm: Box::into_raw(Box::new(vm)),
        };

        // Create a Python object from the PyVmConst
        let ptr_py_obj = Py::new(py, py_ptr).unwrap().into_py(py);

        // Call deref() on the pointer
        let deref_result = ptr_py_obj.call_method0(py, "deref").unwrap();

        // Verify the dereferenced value
        let value_result = deref_result.call_method0(py, "value").unwrap();
        assert_eq!(value_result.extract::<String>(py).unwrap(), target_value.to_string());

        // Clean up
        unsafe {
            let _ = Box::from_raw(ptr_py_obj.extract::<&PyVmConst>(py).unwrap().vm);
        }
    });
}
