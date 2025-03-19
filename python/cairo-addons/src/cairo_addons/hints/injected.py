# A module that contains functions "injected" into the execution scope of hints in the Rust VM.
# The purpose of these functions is to provide a way to serialize Cairo variables using Pythonic Hints running on the Rust VM.
from typing import Callable


def set_identifiers(context: Callable[[], dict]):
    """Load program identifiers from JSON and store them in the provided context object."""
    from starkware.cairo.lang.compiler.program import Program

    __program_json__ = context().get("__program_json__")
    if __program_json__ is None:
        context()["py_identifiers"] = None
        return
    program = Program.Schema().loads(__program_json__)
    context()["py_identifiers"] = program.identifiers


def set_program_input(context: Callable[[], dict]):
    """Load program input from JSON and store it in the provided context object."""
    context()["program_input"] = context().get("program_input")


def prepare_context(context: Callable[[], dict]):
    """Create and register the serializer function in the provided context object."""
    import logging

    context()["logger"] = logging.getLogger("TRACE")

    def serialize(variable, segments, program_identifiers, dict_manager):
        """Serialize a Cairo variable using the Serde class."""

        from starkware.cairo.lang.compiler.identifier_manager import IdentifierError
        from starkware.cairo.lang.vm.relocatable import RelocatableValue

        from cairo_addons.vm import Relocatable as RustRelocatable
        from tests.utils.serde import Serde

        if isinstance(variable, int):
            return variable

        # Create Serde instance
        serde_cls = Serde(
            segments=segments,
            program_identifiers=program_identifiers,
            dict_manager=dict_manager,
        )

        if isinstance(variable, RelocatableValue) or isinstance(
            variable, RustRelocatable
        ):
            return serde_cls.serialize_list(variable)

        try:
            # Rust
            if variable.is_pointer():
                return serde_cls.serialize_pointers(
                    tuple(variable.type_path), variable.address_
                )
        except IdentifierError:
            pass

        type_path = None
        try:
            # Rust
            type_path = tuple(variable.type_path)
        except IdentifierError:
            # Python
            type_path = variable._struct_definition.full_name.path
        return serde_cls.serialize_type(type_path, variable.address_)

    context()["serialize"] = serialize

    from tests.utils.args_gen import _gen_arg

    context()["_gen_arg"] = _gen_arg


def initialize_hint_environment(context: Callable[[], dict]):
    """Initialize the hint environment with all necessary components.

    Args:
        context: The context object to store the context variables in.
    """
    # First load identifiers
    set_identifiers(context)
    # Then load program input
    set_program_input(context)
    # Then create and register serializer
    prepare_context(context)
