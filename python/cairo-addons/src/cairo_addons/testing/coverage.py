from typing import List

import polars as pl
from starkware.cairo.lang.compiler.program import Program


def line_to_pc_df(
    cairo_programs: List[Program], program_base: int = 1
) -> List[pl.DataFrame]:
    dfs = []
    for cairo_program in cairo_programs:
        if cairo_program.debug_info is None:
            raise ValueError("Program debug info is not available")

        line_to_pc = (
            pl.DataFrame(
                {
                    "pc": key + program_base,
                    "instruction": str(instruction_location.inst),
                    "line_number": list(
                        range(
                            instruction_location.inst.start_line,
                            instruction_location.inst.end_line + 1,
                        )
                    ),
                }
                for key, instruction_location in cairo_program.debug_info.instruction_locations.items()
            )
            .lazy()
            .with_columns(
                # Split instruction into filename, position
                pl.col("instruction")
                .str.split_exact(":", 1)
                .struct.rename_fields(["filename", "position"]),
            )
            .unnest("instruction")
            .drop("position")
            .explode("line_number")
        ).collect()

        # Only keep the first occurrence of the lines
        line_to_first_pc = line_to_pc.select(["line_number", "filename", "pc"]).unique(
            subset=["line_number"], keep="first"
        )
        dfs.append(line_to_first_pc)

    return dfs


def coverage_from_trace(
    cairo_file_name: str,
    line_to_first_pc_df: pl.DataFrame,
    trace: pl.DataFrame,
):

    # Join with the trace to get the coverage
    coverage = (
        trace.lazy()
        .select(["pc"])
        .join(line_to_first_pc_df.lazy(), how="right", on="pc")
        .drop("pc")
        .with_columns(
            filename=(
                pl.when(pl.col("filename") == "")
                .then(pl.lit(str(cairo_file_name)))
                .otherwise(pl.col("filename"))
            ),
        )
        .filter(~pl.col("filename").str.contains(".venv"))
        .filter(~pl.col("filename").str.contains("test_"))
    ).collect()

    return coverage
