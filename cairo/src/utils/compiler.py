from pathlib import Path

from starkware.cairo.lang.cairo_constants import DEFAULT_PRIME
from starkware.cairo.lang.compiler.cairo_compile import compile_cairo, get_module_reader
from starkware.cairo.lang.compiler.preprocessor.default_pass_manager import (
    default_pass_manager,
)
from starkware.cairo.lang.compiler.program import CairoHint

from src.utils.constants import CHAIN_ID

dict_manager = """
if '__dict_manager' not in globals():
    from starkware.cairo.common.dict import DictManager
    __dict_manager = DictManager()
"""

dict_copy = """
from starkware.cairo.common.dict import DictTracker

if ids.new_start.address_.segment_index in __dict_manager.trackers:
    raise ValueError(f"Segment {ids.new_start.address_.segment_index} already exists in __dict_manager.trackers")

data = __dict_manager.trackers[ids.dict_start.address_.segment_index].data.copy()
__dict_manager.trackers[ids.new_start.address_.segment_index] = DictTracker(
    data=data,
    current_ptr=ids.new_end.address_,
)
"""

dict_squash = """
from starkware.cairo.common.dict import DictTracker

data = __dict_manager.get_dict(ids.dict_accesses_end).copy()
base = segments.add()
assert base.segment_index not in __dict_manager.trackers
__dict_manager.trackers[base.segment_index] = DictTracker(
    data=data, current_ptr=base
)
memory[ap] = base
"""

block = f"""
{dict_manager}
from tests.utils.hints import gen_arg_pydantic

ids.block = gen_arg_pydantic(__dict_manager, segments, program_input["block"])
"""

state = f"""
{dict_manager}
from tests.utils.hints import gen_arg_pydantic

ids.state = gen_arg_pydantic(__dict_manager, segments, program_input["state"])
"""

chain_id = f"""
ids.chain_id = {CHAIN_ID}
"""

block_hashes = """
import random

ids.block_hashes = segments.gen_arg([random.randint(0, 2**128 - 1) for _ in range(256 * 2)])
"""

hints = {
    "dict_manager": dict_manager,
    "dict_copy": dict_copy,
    "dict_squash": dict_squash,
    "block": block,
    "state": state,
    "chain_id": chain_id,
    "block_hashes": block_hashes,
}


def implement_hints(program):
    return {
        k: [
            (
                CairoHint(
                    accessible_scopes=hint_.accessible_scopes,
                    flow_tracking_data=hint_.flow_tracking_data,
                    code=hints.get(hint_.code, hint_.code),
                )
            )
            for hint_ in v
        ]
        for k, v in program.hints.items()
    }


def cairo_compile(path, debug_info=False, proof_mode=True):
    module_reader = get_module_reader(cairo_path=[str(Path(__file__).parents[2])])

    pass_manager = default_pass_manager(
        prime=DEFAULT_PRIME, read_module=module_reader.read
    )

    return compile_cairo(
        Path(path).read_text(),
        pass_manager=pass_manager,
        debug_info=debug_info,
        add_start=proof_mode,
    )
