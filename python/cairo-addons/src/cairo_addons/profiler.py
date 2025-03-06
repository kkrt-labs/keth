import logging
from time import perf_counter

import polars as pl
from starkware.cairo.lang.compiler.program import Program

logging.basicConfig(format="%(levelname)-8s %(message)s")
logger = logging.getLogger("timer")


def profile_from_trace(program: Program, trace: pl.DataFrame, program_base: int):
    if program.debug_info is None:
        raise ValueError("Program debug info is not available")

    logger.info("Begin profiling")
    start = perf_counter()

    # --- Step 1: Create Debug Info Mapping ---
    # Extract debug information from the program, mapping pc to scope and source location
    debug_info_pc = (
        pl.DataFrame(
            {
                "pc": key + program_base,
                "scope": str(instruction_location.accessible_scopes[-1]),
                "instruction": str(instruction_location.inst),
            }
            for key, instruction_location in program.debug_info.instruction_locations.items()
        )
        .lazy()
        .with_columns(
            # Split instruction into filename, line_number, col
            pl.col("instruction")
            .str.split_exact(":", 2)
            .struct.rename_fields(["filename", "line_number", "col"]),
            # Extract function name from scope (last component after '.')
            function=pl.col("scope").str.split(".").list.get(-1),
        )
        .unnest("instruction")
        .with_columns(pl.col("line_number").cast(pl.Int64))
        .drop("col")  # unused
    )

    # --- Step 2: Reduce Trace Size Before Joining ---
    # Since fp is constant across many pcs within a function call, select unique fp-pc pairs
    # This reduces the trace from potentially millions of rows to the number of function calls only
    fp_to_first_pc = (
        trace.lazy()
        .select(["fp", "pc"])
        .unique(
            subset=["fp"], keep="first"
        )  # Take first pc for each fp; all pcs per fp share the same scope
    )

    # --- Step 3: Join to Build Debug Info per fp ---
    # Join reduced trace with debug info on pc to map each fp to its scope and source info
    debug_info = (
        fp_to_first_pc.join(
            debug_info_pc, on="pc", how="left"
        )  # All remaining pcs are supposed to be in debug_info_pc
        .drop("pc")  # Drop pc immediately as it's no longer needed
        .collect()  # Results in one row per fp
    )

    # --- Step 4: Analyze Frames ---
    # Compute frame statistics using run-length encoding to identify consecutive fp sequences
    frames = (
        trace["fp"]
        .rle()  # Run-length encode fp to get sequences of consecutive fps
        .struct.unnest()  # Unnest into len (sequence length) and value (fp)
        .rename({"value": "fp"})
        .with_columns(
            prev_fp=pl.col("fp").shift(),  # Previous fp for parent identification
            steps=pl.col("len").cum_sum(),  # Cumulative steps up to each sequence
            max_fp=pl.col("fp").cum_max(),  # Max fp seen so far
        )
        .group_by(
            ["fp"], maintain_order=True
        )  # Group by fp to aggregate per function call
        .agg(
            parent=pl.col("prev_fp").first(),  # Parent fp is the first prev_fp
            total_cost=pl.col("len").sum(),  # Total steps executed directly in this fp
            cumulative_cost=(
                pl.col("steps").last() - pl.col("steps").first() + pl.col("len").first()
            ),  # Total steps from start to end, including child calls
            max_fp=pl.col("max_fp").max(),  # Max fp reached during this call
        )
        .select(["parent", pl.all().exclude("parent")])  # Reorder with parent first
        .join(debug_info.select(["fp", "scope"]), how="left", on="fp")  # Add scope
        .filter(pl.col("scope").is_not_null())  # Remove fps without debug info
        .join(
            debug_info.select(["fp", "scope"]),
            how="left",
            right_on="fp",
            left_on="parent",
            suffix="_parent",
        )  # Add parent scope
        .with_columns(
            primitive_call=(pl.col("scope") != pl.col("scope_parent")).fill_null(True)
            # True for non-recursive or top-level calls
        )
    )

    # --- Step 5: Compute Global Cumulative Cost per Scope ---
    # Sum cumulative costs for top-level calls per scope, excluding nested calls
    cumulative_cost = (
        frames.with_columns(
            cum_max_fp=pl.col("max_fp").shift().cum_max().over("scope"),
            # Max fp from previous frames of the same scope
        )
        .filter(
            pl.col("cum_max_fp") < pl.col("fp")
        )  # Keep frames not nested in prior calls
        .group_by(["scope"])
        .agg(cumulative_cost=pl.col("cumulative_cost").sum())
    )

    # --- Step 6: Build Scopes DataFrame ---
    # Aggregate frame data by scope and scope_parent, then by scope
    scopes = (
        frames.group_by(["scope", "scope_parent"])
        .agg(
            primitive_call=pl.col("primitive_call").sum(),  # Total primitive calls
            total_call=pl.col("primitive_call").count(),  # Number of calls
            total_cost=pl.col("total_cost").sum(),  # Total direct steps
            cumulative_cost=(
                pl.col("cumulative_cost") * pl.col("primitive_call")
            ).sum(),
            # Weighted cumulative cost
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
            )  # Struct for parent info
        )
        .group_by("scope")
        .agg(
            primitive_call=pl.col("primitive_call").sum(),
            total_call=pl.col("total_call").sum(),
            total_cost=pl.col("total_cost").sum(),
            cumulative_cost=pl.col("cumulative_cost").sum(),
            parents=pl.col("parent").flatten(),
        )
        .join(cumulative_cost, how="left", on="scope", suffix="_global")
        .with_columns(
            cumulative_cost=pl.col("cumulative_cost_global").fill_null(
                pl.col("cumulative_cost")
            )
            # Use global cumulative cost if available
        )
        .join(
            debug_info.select(
                ["scope", "filename", "line_number", "function"]
            ).unique(),
            how="left",
            on="scope",
        )  # Add source info
    )

    stop = perf_counter()
    logger.info(f"Building dataframe took {stop - start} seconds")

    # --- Step 7: Build Profiling Dictionary ---
    # Convert scopes DataFrame to a dictionary for final output
    keys = scopes.select(["filename", "line_number", "function"]).rows()
    values = scopes.select(
        ["total_call", "primitive_call", "total_cost", "cumulative_cost"]
    ).rows()
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
