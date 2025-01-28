from itertools import accumulate
from pathlib import Path
from typing import Any, List, Optional, Protocol, Tuple, Union

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
from starkware.cairo.lang.vm.memory_dict import UnknownMemoryError
from starkware.cairo.lang.vm.memory_segments import MemorySegmentManager

from cairo_addons.vm import MemorySegmentManager as RustMemorySegmentManager

# Sentinel object for indicating no error in exception handling
NO_ERROR_FLAG = object()


class SerdeProtocol(Protocol):
    def __init__(
        self,
        segments: Union[MemorySegmentManager, RustMemorySegmentManager],
        program: Any,
        dict_manager: Any,
        cairo_file: Optional[Path] = None,
    ): ...

    def get_offsets(self, return_data_types: List[CairoType]) -> List[int]: ...

    def serialize_list(
        self, segment_ptr, item_path: Optional[Tuple[str, ...]] = None, list_len=None
    ): ...

    def serialize(self, cairo_type: CairoType, ap: int, offset: int) -> Any: ...

    @staticmethod
    def filter_no_error_flag(output: List[Any]) -> List[Any]: ...


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


class Serde(SerdeProtocol):
    def __init__(
        self,
        segments: Union[MemorySegmentManager, RustMemorySegmentManager],
        program,
        dict_manager,
        cairo_file=None,
    ):
        self.segments = segments
        self.memory = segments.memory
        self.program = program
        self.dict_manager = dict_manager
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

    def is_pointer_wrapper(self, path: Tuple[str, ...]) -> bool:
        """Returns whether the type is a wrapper to a pointer."""
        members = get_struct_definition(self.program, path).members
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
            full_path = self.main_part + full_path[full_path.index("__main__") + 1 :]

        members = get_struct_definition(self.program, path).members
        return {
            name: self._serialize(member.cairo_type, ptr + member.offset)
            for name, member in members.items()
        }

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
                return None
            if isinstance(cairo_type.pointee, TypeFelt):
                return self.serialize_list(pointee)
            if not isinstance(cairo_type.pointee, TypeStruct):
                raise ValueError(f"Unknown type {cairo_type}")

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
        if isinstance(cairo_type, AliasDefinition):
            return self.serialize_scope(cairo_type.destination, ptr)
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

    def get_offsets(self, cairo_types: List[CairoType]) -> List[int]:
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
            except UnknownMemoryError:
                break
            except Exception:
                # TODO: handle this better as only UnknownMemoryError is expected
                # when accessing invalid memory
                break
        return output

    @staticmethod
    def filter_no_error_flag(output):
        return [x for x in output if x is not NO_ERROR_FLAG]
