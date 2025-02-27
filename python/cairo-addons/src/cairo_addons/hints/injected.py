# A module that contains functions "injected" into the execution scope of hints in the Rust VM.
# The purpose of these functions is to provide a way to serialize Cairo variables using Pythonic Hints running on the Rust VM.
from typing import Callable


def set_identifiers(context: Callable[[], dict]):
    """Load program identifiers from JSON and store them in the provided context object."""
    from starkware.cairo.lang.compiler.program import Program

    __program_json__ = context().get("__program_json__")
    if __program_json__ is None:
        raise ValueError("__program_json__ must be available in the execution scope")

    program = Program.Schema().loads(__program_json__)
    context()["py_identifiers"] = program.identifiers


def create_serializer(context: Callable[[], dict]):
    """Create and register the serializer function in the provided context object."""

    def serialize(variable, segments, program_identifiers, dict_manager):
        """Serialize a Cairo variable using the Serde class."""

        from tests.utils.serde import Serde

        # Create Serde instance
        serde_cls = Serde(
            segments=segments,
            program_identifiers=program_identifiers,
            dict_manager=dict_manager,
        )
        if variable.is_pointer():
            return serde_cls.serialize_pointers(
                tuple(variable.type_path), variable.address_
            )
        return serde_cls.serialize_type(tuple(variable.type_path), variable.address_)

    context()["serialize"] = serialize


def initialize_hint_environment(context: Callable[[], dict]):
    """Initialize the hint environment with all necessary components.

    Args:
        context: The context object to store the context variables in.
    """
    # First load identifiers
    set_identifiers(context)
    # Then create and register serializer
    create_serializer(context)
