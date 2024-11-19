from collections import defaultdict
from dataclasses import fields, is_dataclass
from functools import partial
from importlib import import_module
from typing import Tuple, Union, get_args, get_origin

from starkware.cairo.common.dict import DictTracker
from starkware.cairo.lang.compiler.ast.cairo_types import (
    CairoType,
    TypeFelt,
    TypeStruct,
)
from starkware.cairo.lang.vm.relocatable import MaybeRelocatable, RelocatableValue

from ethereum.base_types import (
    U64,
    U256,
    Bytes,
    Bytes0,
    Bytes8,
    Bytes20,
    Bytes32,
    Bytes256,
    Uint,
)
from ethereum.crypto.hash import Hash32


def gen_arg(dict_manager, segments):
    return partial(_gen_arg, dict_manager, segments)


def _gen_arg(dict_manager, segments, arg_type, arg):
    if get_origin(arg_type) is Union:
        # Union are represented as Enum in Cairo, with 0 pointers for all but one variant.
        struct_ptr = segments.add()
        data = [
            (
                _gen_arg(dict_manager, segments, x_type, arg)
                if isinstance(arg, x_type)
                else 0
            )
            for x_type in get_args(arg_type)
        ]
        # Value types are not pointers by default, so we need to convert them to pointers.
        for i, (x_type, d) in enumerate(zip(get_args(arg_type), data)):
            if isinstance(arg, x_type) and not isinstance(d, RelocatableValue):
                d_ptr = segments.add()
                segments.load_data(d_ptr, [d])
                data[i] = d_ptr
        segments.load_data(struct_ptr, data)
        return struct_ptr

    if get_origin(arg_type) is tuple:
        if len(get_args(arg_type)) == 2 and get_args(arg_type)[1] == Ellipsis:
            # Case a tuple with a variable number of elements, all of the same type.
            # These are represented as a pointer to a struct with a pointer to the elements and the size.
            instances_ptr = segments.add()
            data = [
                _gen_arg(dict_manager, segments, get_args(arg_type)[0], x) for x in arg
            ]
            segments.load_data(instances_ptr, data)
            struct_ptr = segments.add()
            segments.load_data(struct_ptr, [instances_ptr, len(arg)])
            return struct_ptr
        else:
            # Case a tuple with a fixed number of elements, all of different types.
            # These are represented as a pointer to a struct with a pointer to each element.
            struct_ptr = segments.add()
            data = [
                _gen_arg(dict_manager, segments, x_type, x)
                for x_type, x in zip(get_args(arg_type), arg)
            ]
            segments.load_data(struct_ptr, data)
            return struct_ptr

    if get_origin(arg_type) is list:
        # Case list, which is represented as a pointer to a struct with a pointer to the elements and the size.
        instances_ptr = segments.add()
        data = [_gen_arg(dict_manager, segments, get_args(arg_type)[0], x) for x in arg]
        segments.load_data(instances_ptr, data)
        struct_ptr = segments.add()
        segments.load_data(struct_ptr, [instances_ptr, len(arg)])
        return struct_ptr

    if get_origin(arg_type) is dict:
        dict_ptr = segments.add()
        assert dict_ptr.segment_index not in dict_manager.trackers

        data = {
            k: _gen_arg(dict_manager, segments, get_args(arg_type)[1], v)
            for k, v in arg.items()
        }
        if isinstance(arg, defaultdict):
            data = defaultdict(arg.default_factory, data)

        dict_manager.trackers[dict_ptr.segment_index] = DictTracker(
            data=data, current_ptr=dict_ptr
        )
        return dict_ptr

    if arg_type == MaybeRelocatable:
        return arg

    if is_dataclass(arg_type):
        # Dataclasses are represented as a pointer to a struct with the same fields.
        struct_ptr = segments.add()
        data = [
            _gen_arg(dict_manager, segments, f.type, getattr(arg, f.name))
            for f in fields(arg_type)
        ]
        segments.load_data(struct_ptr, data)
        return struct_ptr

    if arg_type in (U256, Hash32, Bytes32, Bytes256):
        if isinstance(arg, U256):
            arg = arg.to_be_bytes32()[::-1]
        base = segments.add()
        segments.load_data(
            base,
            [int.from_bytes(arg[i : i + 16], "little") for i in range(0, len(arg), 16)],
        )
        return base

    if arg_type == Bytes:
        bytes_ptr = segments.add()
        segments.load_data(bytes_ptr, list(arg))
        struct_ptr = segments.add()
        segments.load_data(struct_ptr, [bytes_ptr, len(arg)])
        return struct_ptr

    if arg_type in (bool, U64, Uint, Bytes0, Bytes8, Bytes20):
        return int(arg) if not isinstance(arg, bytes) else int.from_bytes(arg, "little")

    return arg


def to_python_type(cairo_type: CairoType):
    if isinstance(cairo_type, TypeFelt):
        return int

    if isinstance(cairo_type, TypeStruct):
        module = import_module(".".join(cairo_type.scope.path[:-1]))
        type_name = cairo_type.scope.path[-1]
        python_type = getattr(module, type_name.replace("Tuple", ""))
        if type_name.startswith("Tuple"):
            return Tuple[python_type, ...]
        return python_type

    raise NotImplementedError(f"Cairo type {cairo_type} not implemented")
