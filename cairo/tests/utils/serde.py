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
    Tuple,
    Union,
    get_args,
    get_origin,
)

from eth_utils.address import to_checksum_address
from ethereum_types.bytes import Bytes, Bytes0, Bytes8, Bytes20, Bytes32, Bytes256
from ethereum_types.numeric import U256
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
from starkware.cairo.lang.compiler.identifier_manager import MissingIdentifierError
from starkware.cairo.lang.compiler.scoped_name import ScopedName
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager

from ethereum.crypto.hash import Hash32
from tests.utils.args_gen import to_python_type

# Sentinel object for indicating no error in exception handling
NO_ERROR_FLAG = object()


def get_struct_definition(program, path: Tuple[str, ...]) -> StructDefinition:
    """
    Resolves and returns the struct definition for a given path in the Cairo program.
    If the path is an alias (`import T from ...`), it resolves the alias to the actual struct definition.
    If the path is a type definition `using T = V`, it resolves the type definition to the actual struct definition.
    Otherwise, it returns the struct definition directly.
    """
    scope = ScopedName(path)
    identifier = program.identifiers.as_dict()[scope]
    if isinstance(identifier, StructDefinition):
        return identifier
    if isinstance(identifier, TypeDefinition) and isinstance(
        identifier.cairo_type, TypeStruct
    ):
        return get_struct_definition(program, identifier.cairo_type.scope.path)
    if isinstance(identifier, AliasDefinition):
        destination = identifier.destination.path
        return get_struct_definition(program, destination)
    raise ValueError(f"Expected a struct named {path}, found {identifier}")


class Serde:
    def __init__(self, segments: MemorySegmentManager, program, cairo_file=None):
        self.segments = segments
        self.memory = segments.memory
        self.program = program
        self.cairo_file = cairo_file or Path()

    @property
    def main_part(self):
        """
        Resolve the __main__ part of the cairo scope path.
        """
        parts = self.cairo_file.relative_to(Path.cwd()).with_suffix("").parts
        return parts[1:] if parts[0] == "cairo" else parts

    def serialize_pointers(self, path: Tuple[str, ...], ptr):
        """
        Serialize a pointer to a struct, e.g. Uint256*.

        Note: 0 value for pointers types are interpreted as None.
        """
        members = get_struct_definition(self.program, path).members
        output = {}
        for name, member in members.items():
            member_ptr = self.memory.get(ptr + member.offset)
            if member_ptr == 0 and isinstance(member.cairo_type, TypePointer):
                member_ptr = None
            output[name] = member_ptr
        return output

    def serialize_type(self, path: Tuple[str, ...], ptr) -> Any:
        """
        Recursively serialize a Cairo instance, returning the corresponding Python instance.
        """

        if ptr == 0:
            return None

        full_path = path
        if "__main__" in full_path:
            full_path = self.main_part + full_path[full_path.index("__main__") + 1 :]
        python_cls = to_python_type(full_path)

        if get_origin(python_cls) is Annotated:
            python_cls, _ = get_args(python_cls)

        if get_origin(python_cls) is Union:
            value_ptr = self.serialize_pointers(path, ptr)["value"]
            if value_ptr is None:
                return None
            value_path = (
                get_struct_definition(self.program, path)
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
            variant = get_struct_definition(self.program, value_path).members[
                variant_key
            ]

            return self._serialize(variant.cairo_type, value_ptr + variant.offset)

        if get_origin(python_cls) is list:
            mapping_struct_ptr = self.serialize_pointers(path, ptr)["value"]
            mapping_struct_path = (
                get_struct_definition(self.program, path)
                .members["value"]
                .cairo_type.pointee.scope.path
            )
            dict_access_path = (
                get_struct_definition(self.program, mapping_struct_path)
                .members["dict_ptr"]
                .cairo_type.pointee.scope.path
            )
            dict_access_types = get_struct_definition(
                self.program, dict_access_path
            ).members
            key_type = dict_access_types["key"].cairo_type
            value_type = dict_access_types["new_value"].cairo_type
            pointers = self.serialize_pointers(mapping_struct_path, mapping_struct_ptr)
            segment_size = pointers["dict_ptr"] - pointers["dict_ptr_start"]
            dict_ptr = pointers["dict_ptr_start"]
            list_len = pointers["len"]

            dict_repr = {
                self._serialize(key_type, dict_ptr + i): self._serialize(
                    value_type, dict_ptr + i + 2
                )
                for i in range(0, segment_size, 3)
            }
            return [dict_repr[i] for i in range(list_len)]

        if get_origin(python_cls) in (tuple, list, Sequence, abc.Sequence):
            # Tuple and list are represented as structs with a pointer to the first element and the length.
            # The value field is a list of Relocatable (pointers to each element) or Felt (tuple of felts).
            # In usual cairo, a pointer to a struct, (e.g. Uint256*) is actually a pointer to one single
            # memory segment, where values need to be read from consecutive memory cells (e.g. data[i: i + 2]).
            # We don't use this property here for simplicity, each item has consequently its own pointer.
            tuple_struct_ptr = self.serialize_pointers(path, ptr)["value"]
            tuple_struct_path = (
                get_struct_definition(self.program, path)
                .members["value"]
                .cairo_type.pointee.scope.path
            )
            members = get_struct_definition(self.program, tuple_struct_path).members
            if get_origin(python_cls) is tuple and Ellipsis not in get_args(python_cls):
                # These are regular tuples with a given size.
                return tuple(
                    self._serialize(member.cairo_type, tuple_struct_ptr + member.offset)
                    for member in members.values()
                )
            else:
                # These are tuples with a variable size (or list or sequences).
                raw = self.serialize_pointers(tuple_struct_path, tuple_struct_ptr)
                tuple_item_path = members["data"].cairo_type.pointee.scope.path
                resolved_cls = (
                    get_origin(python_cls)
                    if get_origin(python_cls) not in (Sequence, abc.Sequence)
                    else list
                )
                return resolved_cls(
                    [
                        self.serialize_type(tuple_item_path, raw["data"] + i)
                        for i in range(raw["len"])
                    ]
                )

        if get_origin(python_cls) in (Mapping, abc.Mapping, set):
            mapping_struct_ptr = self.serialize_pointers(path, ptr)["value"]
            mapping_struct_path = (
                get_struct_definition(self.program, path)
                .members["value"]
                .cairo_type.pointee.scope.path
            )
            dict_access_path = (
                get_struct_definition(self.program, mapping_struct_path)
                .members["dict_ptr"]
                .cairo_type.pointee.scope.path
            )
            dict_access_types = get_struct_definition(
                self.program, dict_access_path
            ).members
            key_type = dict_access_types["key"].cairo_type
            value_type = dict_access_types["new_value"].cairo_type
            pointers = self.serialize_pointers(mapping_struct_path, mapping_struct_ptr)
            segment_size = pointers["dict_ptr"] - pointers["dict_ptr_start"]
            dict_ptr = pointers["dict_ptr_start"]

            if get_origin(python_cls) is set:
                return {
                    self._serialize(key_type, dict_ptr + i)
                    for i in range(0, segment_size, 3)
                }

            return {
                self._serialize(key_type, dict_ptr + i): self._serialize(
                    value_type, dict_ptr + i + 2
                )
                for i in range(0, segment_size, 3)
            }

        if python_cls in (bytes, bytearray, Bytes, str):
            tuple_struct_ptr = self.serialize_pointers(path, ptr)["value"]
            struct_name = path[-1] + "Struct"
            path = (*path[:-1], struct_name)
            raw = self.serialize_pointers(path, tuple_struct_ptr)
            data = [self.memory.get(raw["data"] + i) for i in range(raw["len"])]
            if python_cls is str:
                return bytes(data).decode()
            return python_cls(data)

        if python_cls and issubclass(python_cls, Exception):
            tuple_struct_ptr = self.serialize_pointers(path, ptr)["value"]
            if not tuple_struct_ptr:
                return NO_ERROR_FLAG
            value_type = (
                get_struct_definition(self.program, path).members["value"].cairo_type
            )
            error_bytes = self._serialize(value_type, tuple_struct_ptr)
            error_message = error_bytes.decode() or ""
            raise python_cls(error_message)

        if python_cls == Bytes256:
            base_ptr = self.memory.get(ptr)
            data = b"".join(
                [
                    self.memory.get(base_ptr + i).to_bytes(16, "little")
                    for i in range(16)
                ]
            )
            return Bytes256(data)

        members = get_struct_definition(self.program, path).members
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

        if python_cls in (U256, Hash32, Bytes32):
            value = value["low"] + value["high"] * 2**128
            if python_cls == U256:
                return U256(value)
            return python_cls(value.to_bytes(32, "little"))

        if python_cls in (Bytes0, Bytes8, Bytes20):
            return python_cls(value.to_bytes(python_cls.LENGTH, "little"))

        # Because some types are wrapped in a value field, e.g. Account{ value: AccountStruct }
        # this may not work, so that we catch the error and try to fallback.
        try:
            signature(python_cls.__init__).bind(None, **kwargs)
            return python_cls(**kwargs)
        except TypeError:
            pass

        if isinstance(value, dict):
            signature(python_cls.__init__).bind(None, **value)
            return python_cls(**value)
        if isinstance(value, Sequence):
            signature(python_cls.__init__).bind(None, *value)
            return python_cls(*value)

        return python_cls(value)

    def serialize_scope(self, scope, scope_ptr):
        # TODO: Remove these once EELS like migration is implemented
        if scope.path == ("src", "model", "model", "State"):
            return self.serialize_state(scope_ptr)
        if scope.path == ("src", "model", "model", "Account"):
            return self.serialize_kakarot_account(scope_ptr)
        if scope.path == ("src", "model", "model", "Stack"):
            return self.serialize_stack(scope_ptr)
        if scope.path == ("src", "model", "model", "Memory"):
            return self.serialize_memory(scope_ptr)
        if scope.path == ("src", "model", "model", "Message"):
            return self.serialize_message(scope_ptr)
        if scope.path == ("src", "model", "model", "EVM"):
            return self.serialize_evm(scope_ptr)
        if scope.path == ("src", "model", "model", "Block"):
            return self.serialize_block_kakarot(scope_ptr)
        if scope.path == ("src", "model", "model", "Option"):
            return self.serialize_option(scope_ptr)
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
                return None
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
            return self.memory.get(ptr)
        if isinstance(cairo_type, TypeStruct):
            return self.serialize_scope(cairo_type.scope, ptr)
        raise ValueError(f"Unknown type {cairo_type}")

    def get_offset(self, cairo_type):
        if hasattr(cairo_type, "members"):
            return len(cairo_type.members)
        else:
            try:
                identifier = get_struct_definition(self.program, cairo_type.scope.path)
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

    # TODO: below functions are deprecated and should be removed
    def serialize_uint256(self, ptr):
        raw = self.serialize_pointers(
            ("starkware", "cairo", "common", "uint256", "Uint256"), ptr
        )
        return raw["low"] + raw["high"] * 2**128

    def serialize_kakarot_account(self, ptr):
        raw = self.serialize_pointers(("src", "model", "model", "Account"), ptr)
        return {
            "code": bytes(self.serialize_list(raw["code"], list_len=raw["code_len"])),
            "code_hash": self.serialize_uint256(raw["code_hash"]),
            "storage": self.serialize_dict(
                raw["storage_start"],
                ("starkware", "cairo", "common", "uint256", "Uint256"),
            ),
            "transient_storage": self.serialize_dict(
                raw["transient_storage_start"],
                ("starkware", "cairo", "common", "uint256", "Uint256"),
            ),
            "valid_jumpdests": self.serialize_dict(raw["valid_jumpdests_start"]),
            "nonce": raw["nonce"],
            "balance": self.serialize_uint256(raw["balance"]),
            "selfdestruct": raw["selfdestruct"],
            "created": raw["created"],
        }

    def serialize_state(self, ptr):
        raw = self.serialize_pointers(("src", "model", "model", "State"), ptr)
        return {
            "accounts": {
                to_checksum_address(f"{key:040x}"): value
                for key, value in self.serialize_dict(
                    raw["accounts_start"], ("src", "model", "model", "Account")
                ).items()
            },
            "events": self.serialize_list(
                raw["events"],
                ("src", "model", "model", "Event"),
                list_len=raw["events_len"],
            ),
        }

    def serialize_eth_transaction(self, ptr):
        raw = self.serialize_type(("src", "model", "model", "Transaction"), ptr)
        return {
            "signer_nonce": raw["signer_nonce"],
            "gas_limit": raw["gas_limit"],
            "max_priority_fee_per_gas": raw["max_priority_fee_per_gas"],
            "max_fee_per_gas": raw["max_fee_per_gas"],
            "destination": (
                to_checksum_address(f'0x{raw["destination"]:040x}')
                if raw["destination"]
                else None
            ),
            "amount": raw["amount"],
            "payload": ("0x" + bytes(raw["payload"][: raw["payload_len"]]).hex()),
            "access_list": (
                raw["access_list"][: raw["access_list_len"]]
                if raw["access_list"] is not None
                else []
            ),
            "chain_id": raw["chain_id"],
        }

    def serialize_message(self, ptr):
        raw = self.serialize_pointers(("src", "model", "model", "Message"), ptr)
        return {
            "bytecode": self.serialize_list(
                raw["bytecode"], list_len=raw["bytecode_len"]
            ),
            "valid_jumpdest": list(
                self.serialize_dict(raw["valid_jumpdests_start"]).keys()
            ),
            "calldata": self.serialize_list(
                raw["calldata"], list_len=raw["calldata_len"]
            ),
            "caller": to_checksum_address(f'{raw["caller"]:040x}'),
            "value": self.serialize_uint256(raw["value"]),
            "parent": self.serialize_type(
                ("src", "model", "model", "Parent"), raw["parent"]
            ),
            "address": to_checksum_address(f'{raw["address"]:040x}'),
            "code_address": to_checksum_address(f'{raw["code_address"]:040x}'),
            "read_only": bool(raw["read_only"]),
            "is_create": bool(raw["is_create"]),
            "depth": raw["depth"],
            "env": self.serialize_type(
                ("src", "model", "model", "Environment"), raw["env"]
            ),
        }

    def serialize_evm(self, ptr):
        evm = self.serialize_type(("src", "model", "model", "EVM"), ptr)
        return {
            "message": evm["message"],
            "return_data": evm["return_data"][: evm["return_data_len"]],
            "program_counter": evm["program_counter"],
            "stopped": bool(evm["stopped"]),
            "gas_left": evm["gas_left"],
            "gas_refund": evm["gas_refund"],
            "reverted": evm["reverted"],
        }

    def serialize_stack(self, ptr):
        raw = self.serialize_pointers(("src", "model", "model", "Stack"), ptr)
        stack_dict = self.serialize_dict(
            raw["dict_ptr_start"],
            ("starkware", "cairo", "common", "uint256", "Uint256"),
            raw["dict_ptr"] - raw["dict_ptr_start"],
        )
        return [
            stack_dict[i]["low"] + stack_dict[i]["high"] * 2**128
            for i in range(raw["size"])
        ]

    def serialize_memory(self, ptr):
        raw = self.serialize_pointers(("src", "model", "model", "Memory"), ptr)
        memory_dict = self.serialize_dict(
            raw["word_dict_start"], dict_size=raw["word_dict"] - raw["word_dict_start"]
        )
        return "".join(
            [f"{memory_dict.get(i, 0):032x}" for i in range(raw["words_len"] * 2)]
        )

    def serialize_rlp_item(self, ptr):
        raw = self.serialize_list(ptr)
        items = []
        for i in range(0, len(raw), 3):
            data_len = raw[i]
            data_ptr = raw[i + 1]
            is_list = raw[i + 2]
            if not is_list:
                items += [bytes(self.serialize_list(data_ptr)[:data_len])]
            else:
                items += [self.serialize_rlp_item(data_ptr)]
        return items

    def serialize_block_kakarot(self, ptr):
        raw = self.serialize_pointers(("src", "model", "model", "Block"), ptr)
        header = self.serialize_type(
            ("src", "model", "model", "BlockHeader"), raw["block_header"]
        )
        if header is None:
            raise ValueError("Block header is None")
        header = {
            **header,
            "withdrawals_root": (
                self.serialize_uint256(header["withdrawals_root"])
                if header["withdrawals_root"] is not None
                else None
            ),
            "parent_beacon_block_root": (
                self.serialize_uint256(header["parent_beacon_block_root"])
                if header["parent_beacon_block_root"] is not None
                else None
            ),
            "requests_root": (
                self.serialize_uint256(header["requests_root"])
                if header["requests_root"] is not None
                else None
            ),
            "extra_data": bytes(header["extra_data"][: header["extra_data_len"]]),
            "bloom": bytes.fromhex("".join(f"{b:032x}" for b in header["bloom"])),
        }
        del header["extra_data_len"]
        return {
            "block_header": header,
            "transactions": self.serialize_list(
                raw["transactions"],
                ("src", "model", "model", "TransactionEncoded"),
                list_len=raw["transactions_len"],
            ),
        }

    def serialize_option(self, ptr):
        raw = self.serialize_pointers(("src", "model", "model", "Option"), ptr)
        if raw["is_some"] == 0:
            return None
        return raw["value"]

    def serialize_list(
        self, segment_ptr, item_path: Optional[Tuple[str, ...]] = None, list_len=None
    ):
        item_identifier = (
            get_struct_definition(self.program, item_path)
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
            list_len = (
                list_len * item_size
                if list_len is not None
                else self.segments.get_segment_size(segment_ptr.segment_index)
            )
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
            # trunk-ignore(ruff/E722)
            except:
                break
        return output

    def serialize_dict(self, dict_ptr, value_scope=None, dict_size=None):
        """
        Serialize a dict.
        """
        if dict_size is None:
            dict_size = self.segments.get_segment_size(dict_ptr.segment_index)
        output = {}
        value_scope = (
            get_struct_definition(self.program, value_scope).full_name
            if value_scope is not None
            else None
        )
        for dict_index in range(0, dict_size, 3):
            key = self.memory.get(dict_ptr + dict_index)
            value_ptr = self.memory.get(dict_ptr + dict_index + 2)
            if value_scope is None:
                output[key] = value_ptr
            else:
                output[key] = (
                    self.serialize_scope(value_scope, value_ptr)
                    if value_ptr != 0
                    else None
                )
        return output
