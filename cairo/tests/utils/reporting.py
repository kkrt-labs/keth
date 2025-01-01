import json
import logging
from pathlib import Path
from time import perf_counter
from typing import List, Union

import polars as pl

from tests.utils.coverage import CoverageFile

logging.basicConfig(format="%(levelname)-8s %(message)s")
logger = logging.getLogger("timer")


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


def profile_from_tracer_data(program, trace, program_base):
    logger.info("Begin profiling")
    start = perf_counter()
    debug_info = (
        pl.DataFrame(
            {
                "pc": key + program_base,
                "scope": str(instruction_location.accessible_scopes[-1]),
                "instruction": str(instruction_location.inst),
            }
            for key, instruction_location in program.debug_info.instruction_locations.items()
        )
        .with_columns(
            pl.col("instruction")
            .str.split_exact(":", 2)
            .struct.rename_fields(["filename", "line_number", "col"]),
            function=pl.col("scope").str.split(".").list.get(-1),
        )
        .unnest("instruction")
        .with_columns(pl.col("line_number").str.to_integer())
        .drop("col")
        .join(trace, how="left", on="pc")
        .drop_nulls()
        .drop(["pc", "ap"])
        .unique(subset=["fp", "scope"])
    )
    frames = (
        trace["fp"]
        .rle()
        .struct.unnest()
        .rename({"value": "fp"})
        .with_columns(prev_fp=pl.col("fp").shift(), steps=pl.col("len").cum_sum())
        .group_by(["fp"], maintain_order=True)
        .agg(
            parent=pl.col("prev_fp").first(),
            total_cost=pl.col("len").sum(),
            cumulative_cost=(
                pl.col("steps").last() - pl.col("steps").first() + pl.col("len").first()
            ),
        )
        .select(["parent", pl.all().exclude("parent")])
        .join(debug_info["fp", "scope"], how="left", on="fp")
        .filter(pl.col("scope").is_not_null())
        .join(
            debug_info["fp", "scope"],
            how="left",
            right_on="fp",
            left_on="parent",
            suffix="_parent",
        )
        .with_columns(
            primitive_call=(pl.col("scope") != pl.col("scope_parent")).fill_null(True),
        )
    )
    scopes = (
        frames.group_by(["scope", "scope_parent"])
        .agg(
            primitive_call=pl.col("primitive_call").sum(),
            total_call=pl.col("primitive_call").count(),
            total_cost=pl.col("total_cost").sum(),
            cumulative_cost=(
                pl.col("cumulative_cost") * pl.col("primitive_call")
            ).sum(),
        )
        .with_columns(
            parent=pl.struct(
                [
                    "scope_parent",
                    "primitive_call",
                    "total_call",
                    "total_cost",
                    "cumulative_cost",
                ]
            )
        )
        .group_by("scope")
        .agg(
            primitive_call=pl.col("primitive_call").sum(),
            total_call=pl.col("total_call").sum(),
            total_cost=pl.col("total_cost").sum(),
            cumulative_cost=pl.col("cumulative_cost").sum(),
            parents=pl.col("parent").flatten(),
        )
        .join(
            debug_info["scope", "filename", "line_number", "function"].unique(),
            how="left",
            on="scope",
        )
    )
    stop = perf_counter()
    logger.info(f"Building dataframe took {stop - start} seconds")
    keys = scopes["filename", "line_number", "function"].rows()
    values = scopes[
        "total_call",
        "primitive_call",
        "total_cost",
        "cumulative_cost",
    ].rows()
    scope_keys = dict(zip(scopes["scope"], keys))
    prof_dict = {}
    for key, value, parents in zip(keys, values, scopes["parents"]):
        prof_dict[key] = value + (
            {
                scope_keys[parent["scope_parent"]]: (
                    parent["total_call"],
                    parent["primitive_call"],
                    parent["total_cost"],
                    parent["cumulative_cost"],
                )
                for parent in parents
                if parent["scope_parent"] is not None
            },
        )
    logger.info(f"Building prof dict took {perf_counter() - stop} seconds")

    return scopes, prof_dict
