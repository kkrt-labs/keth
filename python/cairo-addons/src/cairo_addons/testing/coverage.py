from typing import Any, Dict, List

import polars as pl
from starkware.cairo.lang.compiler.program import Program


def coverage_dataframes(
    cairo_programs: List[Program], cairo_files: List[Any], program_base: int = 1
) -> List[Dict[str, pl.DataFrame]]:
    """
    Create the dataframes required to compute the coverage of a file an execution trace.
    Returns a list of two dataframes, one per cairo file.
    The first dataframe (line_to_pc) maps each program counter to the filename and line number of the instruction.
    The second dataframe (all_statements) contains all the lines of the file with a count of 0, to be updated by the trace.
    """
    dfs = []
    for cairo_program, cairo_file in zip(cairo_programs, cairo_files):
        if cairo_program.debug_info is None:
            raise ValueError("Program debug info is not available")

        data_rows = []
        all_statements_rows = []

        for (
            key,
            instruction_location,
        ) in cairo_program.debug_info.instruction_locations.items():
            data_rows.append(
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
            )

            # For all_statements DataFrame (filter out global scope)
            if len(instruction_location.accessible_scopes) > 1:
                for i in range(
                    instruction_location.inst.start_line,
                    instruction_location.inst.end_line + 1,
                ):
                    all_statements_rows.append(
                        {
                            "filename": instruction_location.inst.input_file.filename,
                            "line_number": i,
                        }
                    )

        # Create line_to_pc DataFrame
        line_to_pc = (
            pl.DataFrame(data_rows)
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

        # Create all_statements DataFrame
        all_statements = (
            # If no statements are found (file only contains imports), create a dummy row
            pl.DataFrame(
                all_statements_rows
                if all_statements_rows
                else [{"filename": "", "line_number": 0}]
            )
            .with_columns(
                filename=(
                    pl.when(pl.col("filename") == "")
                    .then(pl.lit(str(cairo_file)))
                    .otherwise(pl.col("filename"))
                ),
                count=pl.lit(0, dtype=pl.UInt32),
            )
            .select(
                ["count", "filename", "line_number"]
            )  # Explicitly specify column order
        )

        dfs.append(
            {
                "line_to_pc": line_to_pc,
                "all_statements": all_statements,
            }
        )

    return dfs


def coverage_from_trace(
    cairo_file_name: str,
    line_to_pc: pl.DataFrame,
    trace: pl.DataFrame,
):

    # Join with the trace to get the coverage
    coverage = (
        trace["pc"]
        .value_counts()
        .lazy()
        .join(line_to_pc.lazy(), how="right", on="pc")
        .drop("pc")
        .with_columns(
            filename=(
                pl.when(pl.col("filename") == "")
                .then(pl.lit(str(cairo_file_name)))
                .otherwise(pl.col("filename"))
            ),
            count=pl.col("count").fill_nan(0),
        )
        .filter(~pl.col("filename").str.contains(".venv"))
        .filter(~pl.col("filename").str.contains("test_"))
    ).collect()

    return coverage
