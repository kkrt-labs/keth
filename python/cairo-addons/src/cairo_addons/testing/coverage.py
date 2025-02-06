from pathlib import Path
from typing import List

import polars as pl
from starkware.cairo.lang.compiler.program import Program


def coverage_from_trace(
    program: Program, current_file: Path, report: List[pl.DataFrame]
):
    def _coverage(trace: pl.DataFrame, program_base: int):

        if program.debug_info is None:
            raise ValueError("Program debug info is not available")

        coverage = (
            pl.DataFrame(
                {
                    "pc": key + program_base,
                    "instruction": str(instruction_location.inst),
                }
                for key, instruction_location in program.debug_info.instruction_locations.items()
            )
            .with_columns(
                pl.col("instruction")
                .str.split_exact(":", 2)
                .struct.rename_fields(["filename", "line_number", "col"]),
            )
            .unnest("instruction")
            .with_columns(pl.col("line_number").str.to_integer())
            .drop("col")
            .join(trace["pc"].value_counts(), how="right", on="pc")
            .drop("pc")
            .with_columns(
                filename=(
                    pl.when(pl.col("filename") == "")
                    .then(pl.lit(str(current_file)))
                    .otherwise(pl.col("filename"))
                ),
            )
            .filter(~pl.col("filename").str.contains(".venv"))
            .filter(~pl.col("filename").str.contains("test_"))
        )

        report.append(coverage)

        return coverage

    return _coverage
