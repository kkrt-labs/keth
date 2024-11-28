import json
import logging
from pathlib import Path
from typing import Any, Callable, List, TypeVar, Union

from starkware.cairo.lang.compiler.identifier_definition import LabelDefinition
from starkware.cairo.lang.tracer.profile import ProfileBuilder

from tests.utils.coverage import CoverageFile

logging.basicConfig(format="%(levelname)-8s %(message)s")
logger = logging.getLogger("timer")

# A mapping to fix the mismatch between the debug_info and the identifiers.
_label_scope = {
    "src.constants.opcodes_label": "src.constants",
    "src.accounts.library.internal.pow_": "src.accounts.library.internal",
}
T = TypeVar("T", bound=Callable[..., Any])


def dump_coverage(path: Union[str, Path], files: List[CoverageFile]):
    p = Path(path)
    p.mkdir(exist_ok=True, parents=True)
    json.dump(
        {
            "coverage": {
                file.name.split("__main__/")[-1]: {
                    **{line: 0 for line in file.missed},
                    **{line: 1 for line in file.covered},
                }
                for file in files
            }
        },
        open(p / "coverage.json", "w"),
        indent=2,
    )


def profile_from_tracer_data(tracer_data):
    """
    Un-bundle the profile.profile_from_tracer_data to hard fix the opcode_labels name mismatch
    between the debug_info and the identifiers; and adding a try/catch for the traces (pc going out of bounds).
    """

    builder = ProfileBuilder(
        initial_fp=tracer_data.trace[0].fp, memory=tracer_data.memory
    )

    # Functions.
    for name, ident in tracer_data.program.identifiers.as_dict().items():
        if not isinstance(ident, LabelDefinition):
            continue
        builder.function_id(
            name=_label_scope.get(str(name), str(name)),
            inst_location=tracer_data.program.debug_info.instruction_locations[
                ident.pc
            ],
        )

    # Locations.
    for (
        pc_offset,
        inst_location,
    ) in tracer_data.program.debug_info.instruction_locations.items():
        builder.location_id(
            pc=tracer_data.get_pc_from_offset(pc_offset),
            inst_location=inst_location,
        )

    # Samples.
    for trace_entry in tracer_data.trace:
        try:
            builder.add_sample(trace_entry)
        except KeyError:
            pass

    return builder.dump()
