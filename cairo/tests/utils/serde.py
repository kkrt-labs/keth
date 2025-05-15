"""
Cairo Type System Serialization/Deserialization

This module implements the serialization of Cairo types to Python types.
It is part of the "soft type system" that allows seamless conversion between Python and Cairo,
and mirrors @args_gen.py.

The serialization process is based on the Cairo type system rules defined in @args_gen.py.
Given a Cairo type, we know what the memory layout is, and how to retrieve individual values from the memory.

For example, a Union type is represented as a struct with a pointer to the memory segment of the
variant.  The only value that is not a `0` is the pointer to the memory segment of the variant.
Thus, when deserializing a Union type, we first get the pointer to the variant struct, then check
which member has a non-zero pointer value. This non-zero pointer indicates which variant is actually
present, and points to the memory segment containing that variant's data. If we find more or less
than exactly one non-zero pointer, it means the Union is malformed.
Once we have the variant pointer, we can deserialize the variant by recursively calling the
serialization function.
"""

from collections import abc
from dataclasses import is_dataclass
from inspect import signature
from itertools import accumulate
from pathlib import Path
from typing import (
    Annotated,
    Any,
    List,
    Mapping,
    Optional,
    Sequence,
    Set,
    Tuple,
    Union,
    get_args,
    get_origin,
)

from ethereum.prague.fork_types import Account, Address
from ethereum.prague.state import State, TransientStorage
from ethereum.prague.trie import Trie
from ethereum.prague.vm.exceptions import InvalidOpcode
from ethereum.crypto.alt_bn128 import BNF, BNF2, BNF12
from ethereum.crypto.hash import Hash32
from ethereum.crypto.kzg import BLSFieldElement, KZGCommitment, KZGProof
from ethereum_types.bytes import (
    Bytes,
    Bytes0,
    Bytes1,
    Bytes4,
    Bytes8,
    Bytes20,
    Bytes32,
    Bytes48,
    Bytes256,
)
from ethereum_types.numeric import U256
from py_ecc.fields import optimized_bls12_381_FQ as BLSF
from py_ecc.fields import optimized_bls12_381_FQ2 as BLSF2
from py_ecc.fields import optimized_bls12_381_FQ12 as BLSF12
from py_ecc.optimized_bls12_381.optimized_curve import Z1, Z2, Optimized_Point3D
from starkware.cairo.common.dict import DictManager
from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.ast.cairo_types import (
    CairoType,
    TypeFelt,
    TypePointer,
    TypeStruct,
    TypeTuple,
)
from starkware.cairo.lang.compiler.identifier_definition import (
    AliasDefinition,
    StructDefinition,
    TypeDefinition,
)
from starkware.cairo.lang.compiler.identifier_manager import (
    IdentifierManager,
    MissingIdentifierError,
)
from starkware.cairo.lang.compiler.scoped_name import ScopedName
from starkware.cairo.lang.vm.memory_dict import UnknownMemoryError
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager

from cairo_addons.rust_bindings.vm import DictManager as RustDictManager
from cairo_addons.rust_bindings.vm import (
    MemorySegmentManager as RustMemorySegmentManager,
)
from cairo_addons.rust_bindings.vm import (
    blake2s_hash_many,
)
from cairo_addons.testing.compiler import get_main_path
from tests.utils.args_gen import (
    U384,
    BLSPubkey,
    FlatState,
    FlatTransientStorage,
    G1Compressed,
    Memory,
    MutableBloom,
    Stack,
    builtins_exception_classes,
    ethereum_exception_classes,
    to_python_type,
    vm_exception_classes,
)

# Sentinel object for indicating no error in exception handling
NO_ERROR_FLAG = object()


class DictConsistencyError(Exception):
    def __init__(
        self, dict_access_path: Tuple[str, ...], dict_ptr: int, dict_ptr_value: int
    ):
        self.dict_access_path = dict_access_path
        self.dict_ptr = dict_ptr
        self.dict_ptr_value = dict_ptr_value

    def __str__(self):
        return f"Dict consistency error: {self.dict_access_path}, dict_ptr: {self.dict_ptr}, dict_ptr_value: {self.dict_ptr_value}"


def get_struct_definition(
    program_identifiers: IdentifierManager, path: Tuple[str, ...]
) -> StructDefinition:
    """
    Resolves and returns the struct definition for a given path in the Cairo program.
    If the path is an alias (`import T from ...`), it resolves the alias to the actual struct definition.
    If the path is a type definition `using T = V`, it resolves the type definition to the actual struct definition.
    Otherwise, it returns the struct definition directly.
    """
    scope = ScopedName(path)
    identifier = program_identifiers.as_dict()[scope]
    if isinstance(identifier, StructDefinition):
        return identifier
    if isinstance(identifier, TypeDefinition) and isinstance(
        identifier.cairo_type, TypeStruct
    ):
        return get_struct_definition(
            program_identifiers, identifier.cairo_type.scope.path
        )
    if isinstance(identifier, AliasDefinition):
        destination = identifier.destination.path
        return get_struct_definition(program_identifiers, destination)
    raise ValueError(f"Expected a struct named {path}, found {identifier}")


class Serde:
    def __init__(
        self,
        segments: Union[MemorySegmentManager, RustMemorySegmentManager],
        program_identifiers: IdentifierManager,
        dict_manager: Union[DictManager, RustDictManager],
        cairo_file=None,
    ):
        self.segments = segments
        self.memory = segments.memory if segments else None
        self.program_identifiers = program_identifiers
        self.dict_manager = dict_manager
        self.cairo_file = cairo_file or Path()

    def serialize_pointers(self, path: Tuple[str, ...], ptr):
        """
        Serialize a pointer to a struct, e.g. Uint256*.

        Note: 0 value for pointers types are interpreted as None.
        """
        members = get_struct_definition(self.program_identifiers, path).members
        output = {}
        for name, member in members.items():
            member_ptr = self.memory.get(ptr + member.offset)
            if member_ptr == 0 and isinstance(member.cairo_type, TypePointer):
                member_ptr = None
            output[name] = member_ptr
        return output

    def is_pointer_wrapper(self, path: Tuple[str, ...]) -> bool:
        """Returns whether the type is a wrapper to a pointer."""
        members = get_struct_definition(self.program_identifiers, path).members
        if len(members) != 1:
            return False
        return isinstance(list(members.values())[0].cairo_type, TypePointer)

    def serialize_type(self, path: Tuple[str, ...], ptr) -> Any:
        """
        Recursively serialize a Cairo instance, returning the corresponding Python instance.
        """

        if ptr == 0:
            return None

        full_path = path
        if "__main__" in full_path:
            full_path = (
                get_main_path(self.cairo_file)
                + full_path[full_path.index("__main__") + 1 :]
            )
        python_cls = to_python_type(full_path)
        origin_cls = get_origin(python_cls)
        annotations = []

        if get_origin(python_cls) is Annotated:
            python_cls, *annotations = get_args(python_cls)
            origin_cls = get_origin(python_cls)

        # arg_type = Optional[T, U] <=> arg_type_origin = Union[T, U, None]
        if origin_cls is Union and get_args(python_cls)[-1] is type(None):
            # Get the value pointer: if it's zero, return None.
            # Otherwise, consider this the non-optional type:
            value_ptr = self.serialize_pointers(path, ptr)["value"]
            if value_ptr is None:
                return None
            non_optional_path = full_path[:-1] + (
                full_path[-1].removeprefix("Optional"),
            )
            inner_type = (
                get_struct_definition(self.program_identifiers, path)
                .members["value"]
                .cairo_type.pointee
            )
            if isinstance(inner_type, TypeFelt):
                # Optional felt values are represented as a struct with a pointer to the felt value.
                # Dereference the pointer to get the felt value.
                return self.serialize_type(non_optional_path, value_ptr)
                # Optional struct are a pointer to the InnerStruct type, so just serialize it as the
                # non-optional type
            return self.serialize_type(non_optional_path, ptr)

        if origin_cls is Union:
            value_ptr = self.serialize_pointers(path, ptr)["value"]
            if value_ptr is None:
                return None
            value_path = (
                get_struct_definition(self.program_identifiers, path)
                .members["value"]
                .cairo_type.pointee.scope.path
            )
            # Union are represented as Struct of pointers in Cairo, with 0 as pointer for all but one variant.
            variant_keys = {
                key
                for key, value in self.serialize_pointers(value_path, value_ptr).items()
                if value != 0 and value is not None
            }
            if len(variant_keys) != 1:
                raise ValueError(
                    f"Expected 1 item only to be relocatable in enum, got {len(variant_keys)}"
                )
            variant_key = list(variant_keys)[0]
            variant = get_struct_definition(
                self.program_identifiers, value_path
            ).members[variant_key]

            return self._serialize(variant.cairo_type, value_ptr + variant.offset)

        if python_cls in (MutableBloom, Memory) or origin_cls is Stack:
            mapping_struct_ptr = self.serialize_pointers(path, ptr)["value"]
            mapping_struct_path = (
                get_struct_definition(self.program_identifiers, path)
                .members["value"]
                .cairo_type.pointee.scope.path
            )
            dict_access_path = (
                get_struct_definition(self.program_identifiers, mapping_struct_path)
                .members["dict_ptr"]
                .cairo_type.pointee.scope.path
            )
            dict_access_types = get_struct_definition(
                self.program_identifiers, dict_access_path
            ).members
            key_type = dict_access_types["key"].cairo_type
            value_type = dict_access_types["new_value"].cairo_type
            pointers = self.serialize_pointers(mapping_struct_path, mapping_struct_ptr)
            segment_size = pointers["dict_ptr"] - pointers["dict_ptr_start"]
            dict_ptr = pointers["dict_ptr_start"]
            data_len = pointers["len"]

            dict_repr = {
                self._serialize(key_type, dict_ptr + i): self._serialize(
                    value_type, dict_ptr + i + 2
                )
                for i in range(0, segment_size, 3)
            }
            if python_cls is Memory:
                # For bytearray, convert Bytes1 objects to integers
                return Memory(
                    int.from_bytes(dict_repr.get(i, b"\x00"), "little")
                    for i in range(data_len)
                )

            if python_cls is MutableBloom:
                return MutableBloom(
                    int.from_bytes(dict_repr[i], "little") for i in range(data_len)
                )

            return [dict_repr[i] for i in range(data_len)]

        if origin_cls in (tuple, list, Sequence, abc.Sequence):
            # Tuple and list are represented as structs with a pointer to the first element and the length.
            # The value field is a list of Relocatable (pointers to each element) or Felt (tuple of felts).
            # In usual cairo, a pointer to a struct, (e.g. Uint256*) is actually a pointer to one single
            # memory segment, where values need to be read from consecutive memory cells (e.g. data[i: i + 2]).
            # We don't use this property here for simplicity, each item has consequently its own pointer.
            tuple_struct_ptr = self.serialize_pointers(path, ptr)["value"]
            tuple_struct_path = (
                get_struct_definition(self.program_identifiers, path)
                .members["value"]
                .cairo_type.pointee.scope.path
            )
            members = get_struct_definition(
                self.program_identifiers, tuple_struct_path
            ).members
            if origin_cls is tuple and (
                (Ellipsis not in get_args(python_cls))
                or (Ellipsis in get_args(python_cls) and len(annotations) == 1)
            ):
                # These are regular tuples with a given size.
                result = tuple(
                    self._serialize(member.cairo_type, tuple_struct_ptr + member.offset)
                    for member in members.values()
                )
                # Convert from affine space to projective space for BLS12-381 over Fq.
                if python_cls == Optimized_Point3D[BLSF]:
                    if result == (BLSF.zero(), BLSF.zero()):
                        result = Z1
                    else:
                        result = (result[0], result[1], BLSF.one())

                # Convert from affine space to projective space for BLS12-381 over Fq2.
                if python_cls == Optimized_Point3D[BLSF2]:
                    if result == (BLSF2.zero(), BLSF2.zero()):
                        result = Z2
                    else:
                        result = (result[0], result[1], BLSF2.one())

                if (
                    annotations
                    and len(annotations) == 1
                    and annotations[0] != len(result)
                ):
                    raise ValueError(
                        f"Expected tuple of size {annotations[0]}, got {len(result)}"
                    )
                return result
            else:
                # These are tuples with a variable size (or list or sequences).
                raw = self.serialize_pointers(tuple_struct_path, tuple_struct_ptr)
                tuple_item_path = members["data"].cairo_type.pointee.scope.path
                resolved_cls = (
                    origin_cls if origin_cls not in (Sequence, abc.Sequence) else list
                )
                return resolved_cls(
                    [
                        self.serialize_type(tuple_item_path, raw["data"] + i)
                        for i in range(raw["len"])
                    ]
                )

        if origin_cls in (Mapping, abc.Mapping, set):
            mapping_struct_ptr = self.serialize_pointers(path, ptr)["value"]
            mapping_struct_path = (
                get_struct_definition(self.program_identifiers, path)
                .members["value"]
                .cairo_type.pointee.scope.path
            )

            # Recursively serialize the mapping struct with support
            # for copying from a previous mapping segment.
            return self._serialize_mapping_struct(
                mapping_struct_path, mapping_struct_ptr, origin_cls
            )

        if python_cls in (bytes, bytearray, Bytes, str):
            tuple_struct_ptr = self.serialize_pointers(path, ptr)["value"]
            struct_name = path[-1] + "Struct"
            path = (*path[:-1], struct_name)
            raw = self.serialize_pointers(path, tuple_struct_ptr)
            data = [self.memory.get(raw["data"] + i) for i in range(raw["len"])]
            if python_cls is str:
                return bytes(data).decode()
            return python_cls(data)

        if (
            python_cls
            and isinstance(python_cls, type)
            and issubclass(python_cls, Exception)
        ):
            error_value = self.serialize_pointers(path, ptr)["value"]
            if error_value == 0:
                return NO_ERROR_FLAG
            error_bytes = error_value.to_bytes(32, "big")
            ascii_value = error_bytes.decode().strip("\x00")
            actual_error_cls = next(
                (
                    cls
                    for name, cls in vm_exception_classes
                    + ethereum_exception_classes
                    + builtins_exception_classes
                    if name == ascii_value
                ),
                None,
            )
            if actual_error_cls is InvalidOpcode:
                return actual_error_cls(
                    0
                )  # Return 0 by default, as we don't pass the argument in cairo
            if actual_error_cls is None:
                raise ValueError(f"Unknown error class: {ascii_value}")
            return actual_error_cls()

        if python_cls == Bytes256:
            base_ptr = self.memory.get(ptr)
            data = b"".join(
                [
                    self.memory.get(base_ptr + i).to_bytes(1, "little")
                    for i in range(256)
                ]
            )
            return Bytes256(data)

        # Special handling of the State and TransientStorage types, because the cairo representation is recursive-based (no snapshots list);
        # we need to re-construct the snapshots list from the recursive representation.
        if python_cls is State:
            return self.serialize_state(ptr)

        if python_cls is TransientStorage:
            return self.serialize_transient_storage(ptr)

        members = get_struct_definition(self.program_identifiers, path).members
        kwargs = {
            name: self._serialize(member.cairo_type, ptr + member.offset)
            for name, member in members.items()
        }

        if python_cls is None:
            return kwargs

        value = kwargs.get("value")
        if isinstance(members["value"].cairo_type, TypePointer) and value is None:
            # A None pointer is valid for pointer types, meaning just that the struct is not present.
            return None

        if python_cls in (U256, Hash32, Bytes32, BLSFieldElement):
            value = value["low"] + value["high"] * 2**128
            if python_cls == U256:
                return U256(value)
            return python_cls(value.to_bytes(32, "little"))

        if python_cls in (
            U384,
            Bytes48,
            KZGCommitment,
            G1Compressed,
            BLSPubkey,
            KZGProof,
        ):
            # U384 is represented as a struct with 4 fields: d0, d1, d2, d3
            # Each field is a felt representing 96 bits
            d0 = value["d0"]
            d1 = value["d1"]
            d2 = value["d2"]
            d3 = value["d3"]

            # Combine the fields to create the full 384-bit integer
            combined_value = d0 + (d1 << 96) + (d2 << 192) + (d3 << 288)
            if python_cls == U384:
                return U384(combined_value)
            return python_cls(combined_value.to_bytes(48, "little"))

        if python_cls in (Bytes0, Bytes1, Bytes4, Bytes8, Bytes20):
            return python_cls(value.to_bytes(python_cls.LENGTH, "little"))

        if python_cls in (BNF, BLSF):
            # The BNF and BLSF constructors accept int only, not tuples or U384.
            return python_cls(int(value["c0"]))

        if python_cls in (BNF2, BNF12, BLSF2, BLSF12):
            # The BNF<N> and BLSF<N> constructors don't accept named tuples
            # and values are integers, not U384.
            values = [int(v) for v in value.values()]
            return python_cls(tuple(values))

        # Because some types are wrapped in a value field, e.g. Account{ value: AccountStruct }
        # this may not work, so that we catch the error and try to fallback.
        try:
            signature(python_cls.__init__).bind(None, **kwargs)
            return python_cls(**kwargs)
        except TypeError:
            pass

        if is_dataclass(get_origin(python_cls)) or is_dataclass(python_cls):
            # Adjust int fields if they exceed 2**128 by subtracting DEFAULT_PRIME
            # and filter out the NO_ERROR_FLAG, replacing it with None

            # Note: we skip any `Hashed` types, as they are not represented with negative values
            adjusted_value = {
                k: (
                    None
                    if v is NO_ERROR_FLAG
                    else (v - DEFAULT_PRIME if isinstance(v, int) and v > 2**128 else v)
                )
                for k, v in value.items()
            }

            return python_cls(**adjusted_value)

        if isinstance(value, dict):
            signature(python_cls.__init__).bind(None, **value)
            return python_cls(**value)
        if isinstance(value, Sequence):
            signature(python_cls.__init__).bind(None, *value)
            return python_cls(*value)

        return python_cls(value)

    def serialize_scope(self, scope, scope_ptr):
        try:
            return self.serialize_type(scope.path, scope_ptr)
        except MissingIdentifierError:
            return scope_ptr

    def _serialize(self, cairo_type, ptr, length=1):
        if isinstance(cairo_type, TypePointer):
            # A pointer can be a pointer to one single struct or to the beginning of a list of structs.
            # As such, every pointer is considered a list of structs, with length 1 or more.
            pointee = self.memory.get(ptr)
            # Edge case: 0 pointers are not pointer but no data
            if pointee == 0:
                if isinstance(cairo_type.pointee, TypeFelt):
                    return None
                # If the pointer is to an exception, return the error flag
                python_cls = to_python_type(cairo_type.pointee.scope.path)
                return (
                    NO_ERROR_FLAG
                    if isinstance(python_cls, type)
                    and issubclass(python_cls, Exception)
                    else None
                )
            if isinstance(cairo_type.pointee, TypeFelt):
                return self.serialize_list(pointee)
            serialized = self.serialize_list(
                pointee, cairo_type.pointee.scope.path, list_len=length
            )
            if len(serialized) == 1:
                return serialized[0]
            return serialized
        if isinstance(cairo_type, TypeTuple):
            raw = [
                self._serialize(m.typ, ptr + i)
                for i, m in enumerate(cairo_type.members)
            ]
            filtered = [x for x in raw if x is not NO_ERROR_FLAG]
            return filtered[0] if len(filtered) == 1 else filtered
        if isinstance(cairo_type, TypeFelt):
            pointee = self.memory.get(ptr)
            if pointee is None:
                raise UnknownMemoryError(f"Unknown memory at {ptr}")
            return pointee
        if isinstance(cairo_type, TypeStruct):
            return self.serialize_scope(cairo_type.scope, ptr)
        if isinstance(cairo_type, AliasDefinition):
            return self.serialize_scope(cairo_type.destination, ptr)
        raise ValueError(f"Unknown type {cairo_type}")

    def _serialize_mapping_struct(
        self,
        mapping_struct_path,
        mapping_struct_ptr,
        origin_cls,
        # this is used to toggle enforcement of checking
        # if `dict_ptr` is correctly pointing at the next empty memory cell
        check_dict_consistency=True,
    ):
        dict_access_path = (
            get_struct_definition(self.program_identifiers, mapping_struct_path)
            .members["dict_ptr"]
            .cairo_type.pointee.scope.path
        )
        dict_access_types = get_struct_definition(
            self.program_identifiers, dict_access_path
        ).members

        python_key_type = to_python_type(dict_access_types["key"].cairo_type)
        # Some mappings have keys that are hashed. In that case, the cairo type name starts with "Hashed".
        # but in reality, the key is a felt.
        cairo_key_type = (
            TypeFelt()
            if dict_access_types["key"].cairo_type.scope.path[-1].startswith("Hashed")
            else dict_access_types["key"].cairo_type
        )

        value_type = dict_access_types["new_value"].cairo_type
        pointers = self.serialize_pointers(mapping_struct_path, mapping_struct_ptr)
        segment_size = pointers["dict_ptr"] - pointers["dict_ptr_start"]
        dict_ptr = pointers["dict_ptr_start"]

        # Invariant Testing:
        # We need to ensure that the last dict_ptr points properly
        # since they might have been updated by reading the `original_storage_trie` field of the state.
        if check_dict_consistency and self.memory.get(pointers["dict_ptr"]) is not None:
            raise DictConsistencyError(
                dict_access_path,
                pointers["dict_ptr"],
                self.memory.get(pointers["dict_ptr"]),
            )

        dict_segment_data = {
            self._serialize(cairo_key_type, dict_ptr + i): self._serialize(
                value_type, dict_ptr + i + 2
            )
            for i in range(0, segment_size, 3)
        }

        # In case this is a copy of a previous dict, we serialize the original dict.
        # This is because the dict_tracker has the original values, but cairo memory
        # does not: they're held in parent segments.
        # If ptr=0 -> No parent.

        # Note: only "real mappings" have this. Memory and Stack, which are dict-based, do not.
        parent_dict_ptr = pointers.get("parent_dict")
        serialized_original = (
            self._serialize_mapping_struct(
                mapping_struct_path,
                parent_dict_ptr,
                origin_cls,
                check_dict_consistency=False,
            )
            if parent_dict_ptr
            else {}
        )

        serialized_dict = {}
        tracker_data = self.dict_manager.trackers[dict_ptr.segment_index].data
        if isinstance(cairo_key_type, TypeFelt):
            for key, value in tracker_data.items():
                # We skip serialization of null pointers, but serialize values equal to zero
                if value == 0 and self.is_pointer_wrapper(value_type.scope.path):
                    continue
                # Reconstruct the original key from the preimage
                if python_key_type in [
                    Bytes32,
                    Bytes256,
                ]:
                    hashed_key = blake2s_hash_many(key)
                    preimage = b"".join(felt.to_bytes(16, "little") for felt in key)

                    value = dict_segment_data.get(
                        hashed_key, serialized_original.get(preimage)
                    )

                    # If `value` is None, it means the dict tracker has more
                    # data than the corresponding `dict_segment`.
                    # This can occur when serializing snapshots of dictionaries.
                    if value is not None:
                        serialized_dict[preimage] = value

                elif python_key_type == U256:
                    hashed_key = blake2s_hash_many(key)
                    preimage = sum(felt * 2 ** (128 * i) for i, felt in enumerate(key))
                    value = dict_segment_data.get(
                        hashed_key, serialized_original.get(preimage)
                    )
                    if value is not None:
                        serialized_dict[preimage] = value

                elif python_key_type == Bytes:
                    hashed_key = blake2s_hash_many(key) if len(key) != 1 else key[0]
                    preimage = bytes(list(key))
                    value = dict_segment_data.get(
                        hashed_key, serialized_original.get(preimage)
                    )
                    if value is not None:
                        serialized_dict[preimage] = value

                elif get_origin(python_key_type) is tuple:
                    # If the key is a tuple, we're in the case of a Set[Tuple[Address, Bytes32]]]
                    # Where the key is the hashed tuple.]
                    hashed_key = blake2s_hash_many(key)
                    preimage_address = key[0].to_bytes(20, "little")
                    preimage_bytes32 = b"".join(
                        felt.to_bytes(16, "little") for felt in key[1:]
                    )
                    preimage = (preimage_address, preimage_bytes32)
                    value = dict_segment_data.get(
                        hashed_key, serialized_original.get(preimage)
                    )
                    if value is not None:
                        serialized_dict[preimage] = value
                else:
                    raise ValueError(f"Unsupported key type: {python_key_type}")
        else:
            # Even if the dict is not hashed, we need to use the tracker
            # to differentiate between default-values _read_ and explicit writes.
            # Only include keys that were explicitly written to the dict.
            def key_transform(k):
                if python_key_type is Bytes20:
                    return k[0].to_bytes(20, "little")
                else:
                    try:
                        return python_key_type(k[0])
                    except Exception:
                        # If the type is not indexable
                        return python_key_type(k)

            for cairo_key, cairo_value in tracker_data.items():
                preimage = key_transform(cairo_key)

                # For pointer types, a value of 0 means absent - should skip
                is_null_pointer = cairo_value == 0 and self.is_pointer_wrapper(
                    value_type.scope.path
                )
                if is_null_pointer:
                    continue

                value = dict_segment_data.get(
                    preimage, serialized_original.get(preimage)
                )

                if value is not None:
                    serialized_dict[preimage] = value

        if origin_cls is set:
            return set(serialized_dict.keys())

        return serialized_dict

    def serialize_state(self, ptr) -> State:
        """
        Deserialize a Cairo state pointer into a Python State object.
        Reconstructs the snapshots list from Cairo's recursive trie structure.
        """
        value_ptr = self.memory.get(ptr)
        raw_state = self.serialize_pointers(
            ("ethereum", "prague", "state", "StateStruct"), value_ptr
        )

        # Don't fill the snapshots yet
        flat_state = FlatState(
            _main_trie=Trie(
                **self._serialize(
                    self.get_cairo_type_from_path(
                        (
                            "ethereum",
                            "prague",
                            "trie",
                            "TrieAddressOptionalAccountStruct",
                        )
                    ),
                    raw_state["_main_trie"],
                )
            ),
            _storage_tries=Trie(
                **self._serialize(
                    self.get_cairo_type_from_path(
                        (
                            "ethereum",
                            "prague",
                            "trie",
                            "TrieTupleAddressBytes32U256Struct",
                        )
                    ),
                    raw_state["_storage_tries"],
                )
            ),
            _snapshots=[],
            created_accounts=set(
                self._serialize_mapping_struct(
                    ("ethereum", "prague", "fork_types", "SetAddressStruct"),
                    raw_state["created_accounts"],
                    Set[Address],
                ).keys()
            ),
        )

        # Follow parent pointers to reconstruct snapshots
        current_main_dict = self._get_trie_parent_ptr(raw_state["_main_trie"])
        current_storage_dict = self._get_trie_parent_ptr(raw_state["_storage_tries"])

        while current_main_dict and current_storage_dict:

            parent_main_dict = self._get_mapping_parent_ptr(
                current_main_dict,
                ("ethereum", "prague", "fork_types", "MappingAddressAccountStruct"),
            )
            parent_storage_dict = self._get_mapping_parent_ptr(
                current_storage_dict,
                (
                    "ethereum",
                    "prague",
                    "fork_types",
                    "MappingTupleAddressBytes32U256Struct",
                ),
            )

            is_root_state = parent_main_dict is None and parent_storage_dict is None
            snapshot = (
                Trie(
                    flat_state._main_trie.secured,
                    flat_state._main_trie.default,
                    self._serialize_mapping_struct(
                        (
                            "ethereum",
                            "prague",
                            "fork_types",
                            "MappingAddressAccountStruct",
                        ),
                        current_main_dict,
                        Mapping[Address, Optional[Account]],
                    ),
                ),
                Trie(
                    flat_state._storage_tries.secured,
                    flat_state._storage_tries.default,
                    self._serialize_mapping_struct(
                        (
                            "ethereum",
                            "prague",
                            "fork_types",
                            "MappingTupleAddressBytes32U256Struct",
                        ),
                        current_storage_dict,
                        Mapping[Tuple[Address, Bytes32], U256],
                        check_dict_consistency=not is_root_state,
                    ),
                ),
            )
            flat_state._snapshots.append(snapshot)

            current_main_dict = parent_main_dict
            current_storage_dict = parent_storage_dict

        # Reverse the snapshots to match the expected order (older first)
        flat_state._snapshots.reverse()
        return flat_state.to_state()

    def serialize_transient_storage(self, ptr) -> TransientStorage:
        """
        Deserialize a Cairo transient storage pointer into a Python TransientStorage object.
        Reconstructs the snapshots list from Cairo's recursive trie structure.
        """
        value_ptr = self.memory.get(ptr)
        raw_transient_storage = self.serialize_pointers(
            ("ethereum", "prague", "state", "TransientStorageStruct"), value_ptr
        )

        flat_transient_storage = FlatTransientStorage(
            _tries=Trie(
                **self._serialize(
                    self.get_cairo_type_from_path(
                        (
                            "ethereum",
                            "prague",
                            "trie",
                            "TrieTupleAddressBytes32U256Struct",
                        )
                    ),
                    raw_transient_storage["_tries"],
                )
            ),
            _snapshots=[],
        )

        parent_dict = self._get_trie_parent_ptr(raw_transient_storage["_tries"])

        while parent_dict:
            snapshot = Trie(
                flat_transient_storage._tries.secured,
                flat_transient_storage._tries.default,
                self._serialize_mapping_struct(
                    (
                        "ethereum",
                        "prague",
                        "fork_types",
                        "MappingTupleAddressBytes32U256Struct",
                    ),
                    parent_dict,
                    Mapping[Tuple[Address, Bytes32], U256],
                ),
            )
            flat_transient_storage._snapshots.append(snapshot)

            parent_dict = self._get_mapping_parent_ptr(
                parent_dict,
                (
                    "ethereum",
                    "prague",
                    "fork_types",
                    "MappingTupleAddressBytes32U256Struct",
                ),
            )

        # Reverse the snapshots to match the expected order (older first)
        flat_transient_storage._snapshots.reverse()
        return flat_transient_storage.to_transient_storage()

    def _get_mapping_parent_ptr(self, mapping_ptr, mapping_path: Tuple[str, ...]):
        """
        Helper to get the pointer to the parent of a mapping. Returns None if there is no parent.
        """
        if mapping_ptr == 0:
            return None

        fields = self.serialize_pointers(mapping_path, mapping_ptr)
        parent_dict = fields.get("parent_dict")
        return parent_dict if parent_dict != 0 else None

    def _get_trie_parent_ptr(self, trie_ptr):
        """
        Helper to get parent pointer from a trie structure. Returns None if there is no parent.
        """
        if trie_ptr == 0:
            return None

        trie_data = self.serialize_pointers(
            ("ethereum", "prague", "trie", "TrieAddressOptionalAccountStruct"), trie_ptr
        )

        # All tries have the same mapping layout thus the type passed here doesn't matter
        return self._get_mapping_parent_ptr(
            trie_data["_data"],
            ("ethereum", "prague", "fork_types", "MappingAddressAccountStruct"),
        )

    def get_cairo_type_from_path(self, path: Tuple[str, ...]) -> CairoType:
        scope = ScopedName(path)
        identifier = self.program_identifiers.as_dict()[scope]
        if isinstance(identifier, TypeDefinition):
            return identifier.cairo_type
        return TypeStruct(scope=identifier.full_name, location=identifier.location)

    def get_offset(self, cairo_type):
        if hasattr(cairo_type, "members"):
            return len(cairo_type.members)
        else:
            try:
                identifier = get_struct_definition(
                    self.program_identifiers, cairo_type.scope.path
                )
                return len(identifier.members)
            except (ValueError, AttributeError):
                return 1

    def get_offsets(self, cairo_types: List[CairoType]):
        """Given a list of Cairo types, return the cumulative offset for each type."""
        offsets = [self.get_offset(t) for t in reversed(cairo_types)]
        return list(reversed(list(accumulate(offsets))))

    def serialize(self, cairo_type, base_ptr, shift=None, length=None):
        shift = shift if shift is not None else self.get_offset(cairo_type)
        length = length if length is not None else shift
        return self._serialize(cairo_type, base_ptr - shift, length)

    def serialize_list(
        self, segment_ptr, item_path: Optional[Tuple[str, ...]] = None, list_len=None
    ):
        item_identifier = (
            get_struct_definition(self.program_identifiers, item_path)
            if item_path is not None
            else None
        )
        item_type = (
            TypeStruct(item_identifier.full_name)
            if item_identifier is not None
            else TypeFelt()
        )
        item_size = item_identifier.size if item_identifier is not None else 1
        try:
            if segment_ptr.segment_index == 1:
                # edge case:
                # 1. If the segment_index is `1` then it's a pointer on the main segment,
                # under which case the length is hardcoded to `1` - we're certain it's not a list
                list_len = 1
            elif list_len is not None:
                list_len = list_len * item_size
            else:
                list_len = self.segments.get_segment_size(segment_ptr.segment_index)
            if not list_len:
                # In case we were not able to get the list length, we assume it's an arbitrary high value
                list_len = 2**32
        except AssertionError as e:
            if (
                "compute_effective_sizes must be called before get_segment_used_size."
                in str(e)
            ):
                list_len = 1
            else:
                raise e
        output = []
        for i in range(0, list_len, item_size):
            try:
                output.append(self._serialize(item_type, segment_ptr + i))
            # Because there is no way to know for sure the length of the list, we stop when we
            # encounter an error.
            except UnknownMemoryError:
                break
            except DictConsistencyError as e:
                added_info = f"While serializing item {item_path}"
                raise Exception(f"{e}\n{added_info}")
            except Exception as e2:
                raise e2
                # TODO: handle this better as only UnknownMemoryError is expected
                # when accessing invalid memory
        return output

    @staticmethod
    def filter_no_error_flag(output):
        return [x for x in output if x is not NO_ERROR_FLAG]
