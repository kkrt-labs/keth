use cairo_vm::{
    hint_processor::{
        builtin_hint_processor::hint_utils::{
            get_ptr_from_var_name, get_relocatable_from_var_name,
        },
        hint_processor_definition::HintReference,
    },
    math_utils::pow2_const_nz,
    serde::deserialize_program::ApTracking,
    types::{
        errors::math_errors::MathError,
        relocatable::{MaybeRelocatable, Relocatable},
    },
    vm::{errors::hint_errors::HintError, vm_core::VirtualMachine},
    Felt252,
};
use num_bigint::{BigInt, BigUint};
use num_traits::One;

use std::{borrow::Cow, collections::HashMap};
pub fn serialize_sequence(
    name: &str,
    vm: &mut VirtualMachine,
    ids_data: &HashMap<String, HintReference>,
    ap_tracking: &ApTracking,
) -> Result<Vec<Felt252>, HintError> {
    let ptr = get_ptr_from_var_name(name, vm, ids_data, ap_tracking)?;
    let len_addr = (ptr + 1)?;

    let len_felt = vm.get_integer(len_addr)?.into_owned();
    let len =
        len_felt.try_into().map_err(|_| MathError::Felt252ToUsizeConversion(Box::new(len_felt)))?;

    // if len == 0 then no memory is allocated for the sequence
    if len == 0 {
        return Ok(vec![]);
    }

    let data = vm.get_relocatable(ptr)?;

    let values = (0..len)
        .map(|i| {
            let value_addr = (data + i)?;
            vm.get_integer(value_addr).map(|b| b.into_owned())
        })
        .collect::<Result<Vec<_>, _>>();
    values.map_err(|_| HintError::CustomHint(Box::from("Could not serialize sequence")))
}

pub fn deserialize_sequence<T>(
    sequence: Vec<T>,
    vm: &mut VirtualMachine,
) -> Result<Relocatable, HintError>
where
    Felt252: From<T>,
    T: Copy,
    T: std::fmt::Debug,
{
    // Allocate memory segments and write results
    let base = vm.add_memory_segment();
    let data_ptr = vm.add_memory_segment();
    let len = sequence.len();

    // Convert values and write to memory
    let relocatable_values = sequence
        .iter()
        .map(|value| MaybeRelocatable::Int((*value).into()))
        .collect::<Vec<MaybeRelocatable>>();

    vm.segments.write_arg(data_ptr, &relocatable_values)?;
    vm.segments.write_arg(
        base,
        &vec![MaybeRelocatable::from(data_ptr), MaybeRelocatable::Int(len.into())],
    )?;
    Ok(base)
}

#[derive(Debug)]
pub(crate) struct Uint384<'a> {
    pub limbs: [Cow<'a, Felt252>; 4],
}

impl<'a> Uint384<'a> {
    pub(crate) fn from_base_addr(
        addr: Relocatable,
        name: &str,
        vm: &'a VirtualMachine,
    ) -> Result<Self, HintError> {
        let mut limbs = vec![];
        for i in 0..4 {
            limbs.push(vm.get_integer((addr + i)?).map_err(|_| {
                HintError::IdentifierHasNoMember(Box::new((name.to_string(), format!("d{}", i))))
            })?)
        }
        Ok(Self { limbs: limbs.try_into().map_err(|_| HintError::FixedSizeArrayFail(4))? })
    }

    pub(crate) fn from_var_name(
        name: &str,
        vm: &'a VirtualMachine,
        ids_data: &HashMap<String, HintReference>,
        ap_tracking: &ApTracking,
    ) -> Result<Self, HintError> {
        match get_ptr_from_var_name(name, vm, ids_data, ap_tracking) {
            Ok(addr) => Self::from_base_addr(addr, name, vm),
            Err(_) => {
                let base_addr = get_relocatable_from_var_name(name, vm, ids_data, ap_tracking)?;
                Self::from_base_addr(base_addr, name, vm)
            }
        }
    }

    pub(crate) fn from_values(limbs: [Felt252; 4]) -> Self {
        let limbs = limbs.map(Cow::Owned);
        Self { limbs }
    }

    pub(crate) fn insert_from_var_name(
        self,
        var_name: &str,
        vm: &mut VirtualMachine,
        ids_data: &HashMap<String, HintReference>,
        ap_tracking: &ApTracking,
    ) -> Result<(), HintError> {
        let addr = get_relocatable_from_var_name(var_name, vm, ids_data, ap_tracking)?;
        for i in 0..4 {
            vm.insert_value((addr + i)?, self.limbs[i].clone().into_owned())?;
        }
        Ok(())
    }

    pub(crate) fn pack(self) -> BigUint {
        let limbs = self.limbs.iter().map(|x| x.as_ref()).collect::<Vec<&Felt252>>();
        pack(limbs, 96)
    }

    pub(crate) fn pack_bigint(self) -> BigInt {
        self.pack().into()
    }

    pub(crate) fn split(num: &BigUint) -> Self {
        let limbs = split(num, 4, 96);
        Self::from_values(limbs.try_into().unwrap())
    }
}

impl From<&BigUint> for Uint384<'_> {
    fn from(value: &BigUint) -> Self {
        Self::split(value)
    }
}

impl From<Felt252> for Uint384<'_> {
    fn from(value: Felt252) -> Self {
        Self::split(&value.to_biguint())
    }
}

pub(crate) struct Uint256<'a> {
    pub low: Cow<'a, Felt252>,
    pub high: Cow<'a, Felt252>,
}

impl<'a> Uint256<'a> {
    pub(crate) fn from_base_addr(
        addr: Relocatable,
        name: &str,
        vm: &'a VirtualMachine,
    ) -> Result<Self, HintError> {
        Ok(Self {
            low: vm.get_integer(addr).map_err(|_| {
                HintError::IdentifierHasNoMember(Box::new((name.to_string(), "low".to_string())))
            })?,
            high: vm.get_integer((addr + 1)?).map_err(|_| {
                HintError::IdentifierHasNoMember(Box::new((name.to_string(), "high".to_string())))
            })?,
        })
    }

    pub(crate) fn from_var_name(
        name: &str,
        vm: &'a VirtualMachine,
        ids_data: &HashMap<String, HintReference>,
        ap_tracking: &ApTracking,
    ) -> Result<Self, HintError> {
        match get_ptr_from_var_name(name, vm, ids_data, ap_tracking) {
            Ok(addr) => Self::from_base_addr(addr, name, vm),
            Err(_) => {
                let base_addr = get_relocatable_from_var_name(name, vm, ids_data, ap_tracking)?;
                Self::from_base_addr(base_addr, name, vm)
            }
        }
    }

    pub(crate) fn from_values(low: Felt252, high: Felt252) -> Self {
        let low = Cow::Owned(low);
        let high = Cow::Owned(high);
        Self { low, high }
    }

    pub(crate) fn _insert_from_var_name(
        self,
        var_name: &str,
        vm: &mut VirtualMachine,
        ids_data: &HashMap<String, HintReference>,
        ap_tracking: &ApTracking,
    ) -> Result<(), HintError> {
        let addr = get_relocatable_from_var_name(var_name, vm, ids_data, ap_tracking)?;

        vm.insert_value(addr, self.low.into_owned())?;
        vm.insert_value((addr + 1)?, self.high.into_owned())?;

        Ok(())
    }

    pub(crate) fn pack(self) -> BigUint {
        (self.high.to_biguint() << 128) + self.low.to_biguint()
    }

    pub(crate) fn split(num: &BigUint) -> Self {
        let mask_low: BigUint = u128::MAX.into();
        let low = Felt252::from(&(num & mask_low));
        let high = Felt252::from(&(num >> 128));
        Self::from_values(low, high)
    }
}

impl From<&BigUint> for Uint256<'_> {
    fn from(value: &BigUint) -> Self {
        Self::split(value)
    }
}

impl From<Felt252> for Uint256<'_> {
    fn from(value: Felt252) -> Self {
        let (high, low) = value.div_rem(pow2_const_nz(128));
        Self::from_values(low, high)
    }
}

pub(crate) fn split(num: &BigUint, size: usize, num_bits_shift: u32) -> Vec<Felt252> {
    let mut num = num.clone();
    let bitmask = &((BigUint::one() << num_bits_shift) - 1_u32);
    (0..size)
        .map(|_| {
            let a = &num & bitmask;
            num >>= num_bits_shift;
            Felt252::from(&a)
        })
        .collect()
}

pub(crate) fn pack(limbs: Vec<&Felt252>, num_bits_shift: usize) -> BigUint {
    limbs
        .into_iter()
        .enumerate()
        .map(|(i, limb)| limb.as_ref().to_biguint() << (i * num_bits_shift))
        .sum()
}

/// Write a boolean result to AP with offset
pub(crate) fn write_result_to_ap(
    result: impl Into<Felt252>,
    ap_offset: usize,
    vm: &mut VirtualMachine,
) -> Result<(), HintError> {
    vm.insert_value((vm.get_ap() - ap_offset).unwrap(), result.into()).map_err(HintError::Memory)
}

/// Write a collection to an address
pub(crate) fn write_collection_to_addr(
    addr: Relocatable,
    collection: &[impl Into<Felt252> + Clone],
    vm: &mut VirtualMachine,
) -> Result<(), HintError> {
    let args = collection
        .iter()
        .map(|x| MaybeRelocatable::Int(x.clone().into()))
        .collect::<Vec<MaybeRelocatable>>();
    vm.segments.write_arg(addr, &args)?;
    Ok(())
}

/// Write a collection from a variable name
pub(crate) fn write_collection_from_var_name(
    var_name: &str,
    collection: &[impl Into<Felt252> + Clone],
    vm: &mut VirtualMachine,
    ids_data: &HashMap<String, HintReference>,
    ap_tracking: &ApTracking,
) -> Result<(), HintError> {
    let addr = match get_ptr_from_var_name(var_name, vm, ids_data, ap_tracking) {
        Ok(addr) => addr,
        Err(_) => get_relocatable_from_var_name(var_name, vm, ids_data, ap_tracking)?,
    };
    write_collection_to_addr(addr, collection, vm)
}
