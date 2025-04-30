import os
import re
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

import toml
import typer
from rich.console import Console

# Add for formatting
from starkware.cairo.lang.compiler.parser import parse_file

app = typer.Typer(
    help="Cairo Lint - A tool to format Cairo files and remove unused imports.",
    no_args_is_help=True,
)
console = Console()

# --- Constants ---
DISABLE_LINT_COMMENT = "// cairo-lint: disable"
DISABLE_FILE_COMMENT = "// cairo-lint: disable-file"

# --- Regex Patterns ---
# Matches: from path.to.module import identifier
# Matches: from path.to.module import identifier1, identifier2, identifier3
# Captures: 1=module path, 2=identifiers string
SINGLE_IMPORT_RE = re.compile(r"^\s*from\s+([\w.]+)\s+import\s+([\w\s,]+)\s*")

# Matches: from path.to.module import (
# Captures: 1=module path
MULTI_IMPORT_START_RE = re.compile(r"^\s*from\s+([\w.]+)\s+import\s+\(\s*")

# Matches:     identifier,
# Matches:     identifier
# Captures: 1=identifier
MULTI_IMPORT_ITEM_RE = re.compile(r"^\s*(\w+)\s*,?\s*$")

# Matches: )
MULTI_IMPORT_END_RE = re.compile(r"^\s*\)\s*$")


# Change: Add is_disabled flag to ImportInfo.
class ImportInfo:
    """Stores information about a single imported identifier."""

    def __init__(
        self,
        identifier: str,
        module: str,
        line_index: int,
        is_multiline: bool,
        block_start_line: int,
        block_end_line: int,
        is_disabled: bool,
    ):
        self.identifier = identifier
        self.module = module
        self.line_index = line_index  # The specific line the identifier is on
        self.is_multiline = is_multiline
        self.block_start_line = block_start_line  # First line of the import statement
        self.block_end_line = block_end_line  # Last line of the import statement
        self.is_disabled = is_disabled  # If true, this import won't be removed


# Change: Modify parser to check for disable comment on the preceding line.
def parse_cairo_imports(lines: List[str]) -> Tuple[List[ImportInfo], Set[int]]:
    """
    Parses import statements from Cairo code lines.

    Checks for a `// cairo-lint: disable` comment on the line immediately
    preceding an import statement or item to mark it as disabled.

    Returns:
        A tuple containing:
        - A list of ImportInfo objects for each identifier imported.
        - A set of line indices that are part of any import statement.
    """
    imports: List[ImportInfo] = []
    import_lines: Set[int] = set()
    in_multiline_import = False
    current_module = ""
    current_block_start = -1
    block_disabled_by_comment = (
        False  # Tracks disable comment before 'from ... import ('
    )

    for i, line in enumerate(lines):
        # Check for disable comment on the previous line
        preceding_line_is_disable_comment = (
            i > 0 and lines[i - 1].strip() == DISABLE_LINT_COMMENT
        )

        if in_multiline_import:
            import_lines.add(i)
            multi_item_match = MULTI_IMPORT_ITEM_RE.match(line)
            if multi_item_match:
                identifier = multi_item_match.group(1)
                # End line will be updated when ')' is found
                # Item is disabled if comment precedes *this specific line* OR the block start
                item_is_disabled = (
                    preceding_line_is_disable_comment or block_disabled_by_comment
                )
                imports.append(
                    ImportInfo(
                        identifier,
                        current_module,
                        i,
                        True,
                        current_block_start,
                        -1,
                        item_is_disabled,  # Pass disable status
                    )
                )
            elif MULTI_IMPORT_END_RE.match(line):
                # Update block end line for all imports in this block
                for imp in imports:
                    if imp.block_start_line == current_block_start:
                        imp.block_end_line = i
                in_multiline_import = False
                current_module = ""
                current_block_start = -1
                block_disabled_by_comment = False  # Reset block disable status
            # Allow blank lines or comments within multi-line imports
            elif (
                not line.strip()
                or line.strip().startswith("%{")
                or line.strip().startswith("//")
            ):
                pass
            # else: # Potential malformed multi-line import, ignore for now

        else:
            single_match = SINGLE_IMPORT_RE.match(line)
            multi_start_match = MULTI_IMPORT_START_RE.match(line)

            if multi_start_match:
                import_lines.add(i)
                current_module = multi_start_match.group(1)
                in_multiline_import = True
                current_block_start = i
                # Check if the 'from ... import (' line itself was preceded by a disable comment
                block_disabled_by_comment = preceding_line_is_disable_comment
            elif single_match:
                import_lines.add(i)
                module = single_match.group(1)
                identifiers_str = single_match.group(2)
                identifiers = [
                    ident.strip()
                    for ident in identifiers_str.split(",")
                    if ident.strip()
                ]
                for identifier in identifiers:
                    # Import is disabled if comment precedes this line
                    imports.append(
                        ImportInfo(
                            identifier,
                            module,
                            i,
                            False,
                            i,
                            i,
                            preceding_line_is_disable_comment,  # Pass disable status
                        )
                    )

    return imports, import_lines


# Change: Modify process_file to skip checking disabled imports.
def process_file(file_path: Path) -> Optional[str]:
    """
    Processes a single Cairo file to remove unused imports.
    Respects `// cairo-lint: disable` comments on preceding lines.

    Returns:
        The new file content as a string if changes were made, otherwise None.
    """
    try:
        original_content = file_path.read_text()
        ast = parse_file(original_content, str(file_path))
        # Start by formatting the file
        formatted_content = ast.format()
        lines = formatted_content.splitlines()
    except Exception as e:
        console.print(f"[red]Error reading file {file_path}: {e}[/]")
        return None

    if len(lines) > 0 and lines[0].strip() == DISABLE_FILE_COMMENT:
        return None

    imports, import_line_indices = parse_cairo_imports(lines)
    if not imports:
        return None  # No imports found

    code_body_lines = [
        line for i, line in enumerate(lines) if i not in import_line_indices
    ]
    code_body = "\n".join(code_body_lines)

    unused_imports: List[ImportInfo] = []
    for imp in imports:
        # Skip check if the import is disabled by a comment
        if imp.is_disabled:
            continue

        # Check usage (at least 1 usage *outside* the import lines)
        usage_count = find_identifier_usages(imp.identifier, code_body)
        if usage_count == 0:
            # Also ensure the identifier isn't used ONLY on its own import line(s)
            # (This check might be redundant if code_body correctly excludes all import lines)
            # But as a safeguard: check usage in the full original text
            full_usage_count = find_identifier_usages(imp.identifier, original_content)
            # Count how many times it appears *on* its declaration line(s)
            declaration_count = 0
            if imp.is_multiline:
                # Check the specific line the identifier is on
                declaration_count = lines[imp.line_index].count(imp.identifier)
            else:
                # Check the single line import statement
                declaration_count = lines[imp.line_index].count(imp.identifier)

            # If total usages equals usages on declaration line(s), it's unused elsewhere
            if full_usage_count <= declaration_count:
                unused_imports.append(imp)

    if not unused_imports:
        return None  # No removable unused imports found

    # --- Determine lines/items to remove ---
    # (No changes needed in this section, it operates on the filtered unused_imports list)
    lines_to_delete: Set[int] = set()
    single_line_unused: Dict[int, Set[str]] = {}
    multi_line_unused_by_block: Dict[int, Set[str]] = {}
    multi_line_originals_by_block: Dict[int, List[str]] = {}

    # Populate helper dicts (only with non-disabled imports)
    for imp in imports:
        if (
            imp.is_disabled
        ):  # Exclude disabled imports from original counts too for consistency
            continue
        if imp.is_multiline:
            if imp.block_start_line not in multi_line_originals_by_block:
                multi_line_originals_by_block[imp.block_start_line] = []
            multi_line_originals_by_block[imp.block_start_line].append(imp.identifier)

    # Identify unused items (already filtered for disabled ones)
    for imp in unused_imports:  # This list only contains non-disabled, unused imports
        if imp.is_multiline:
            if imp.block_start_line not in multi_line_unused_by_block:
                multi_line_unused_by_block[imp.block_start_line] = set()
            multi_line_unused_by_block[imp.block_start_line].add(imp.identifier)
            lines_to_delete.add(imp.line_index)
        else:
            if imp.line_index not in single_line_unused:
                single_line_unused[imp.line_index] = set()
            single_line_unused[imp.line_index].add(imp.identifier)

    # --- Refine deletions based on whether whole blocks/lines become empty ---
    # (No changes needed in this section)

    # Process multi-line blocks
    for block_start, unused_set in multi_line_unused_by_block.items():
        # Get original identifiers *excluding* disabled ones for this block
        original_non_disabled_set = set()
        for imp in imports:
            if imp.block_start_line == block_start and not imp.is_disabled:
                original_non_disabled_set.add(imp.identifier)

        if not original_non_disabled_set:  # If all originals were disabled, do nothing
            continue

        # If all *non-disabled* items are unused, delete the block (start/end lines)
        # and the lines corresponding to the unused (non-disabled) items.
        if unused_set == original_non_disabled_set:
            block_end = -1
            for imp in imports:
                if imp.block_start_line == block_start:
                    block_end = imp.block_end_line
                    break
            if block_end != -1:
                lines_to_delete.add(block_start)
                lines_to_delete.add(block_end)
                # Ensure all item lines for this block (that weren't disabled) are marked
                for imp in imports:
                    if imp.block_start_line == block_start and not imp.is_disabled:
                        lines_to_delete.add(imp.line_index)

        else:
            # Some non-disabled items are unused, but not all. Keep the start/end lines.
            # Un-delete item lines that correspond to *used* (or disabled) identifiers.
            used_or_disabled_in_block = set()
            for imp in imports:
                if imp.block_start_line == block_start:
                    is_unused_non_disabled = imp.identifier in unused_set
                    if not is_unused_non_disabled:  # Keep if it's used OR disabled
                        used_or_disabled_in_block.add(imp.identifier)
                        if imp.line_index in lines_to_delete:
                            lines_to_delete.remove(imp.line_index)

    # Process single-line imports
    lines_to_rewrite: Dict[int, str] = {}
    for line_idx, unused_set in single_line_unused.items():
        original_identifiers_on_line = []
        module = ""
        is_disabled_line = False  # Check if the whole line was disabled
        for imp in imports:
            if imp.line_index == line_idx:
                original_identifiers_on_line.append(imp.identifier)
                module = imp.module
                is_disabled_line = (
                    imp.is_disabled
                )  # The whole line inherits disabled status

        if is_disabled_line:  # If the line was disabled, don't touch it
            continue

        original_non_disabled_set = set(
            original_identifiers_on_line
        )  # Since is_disabled_line is False

        if original_non_disabled_set == unused_set:
            lines_to_delete.add(line_idx)
        else:
            kept_identifiers = sorted(
                [
                    ident
                    for ident in original_identifiers_on_line
                    if ident not in unused_set
                ]
            )
            if kept_identifiers:
                leading_whitespace = lines[line_idx][
                    : len(lines[line_idx]) - len(lines[line_idx].lstrip())
                ]
                lines_to_rewrite[line_idx] = (
                    f"{leading_whitespace}from {module} import {', '.join(kept_identifiers)}"
                )
            else:
                lines_to_delete.add(line_idx)

    # --- Reconstruct the file ---
    # (No changes needed in this section, it reconstructs based on lines_to_delete/rewrite)
    new_lines: List[str] = []
    removed_any_line = False  # Track if we actually removed something
    for i, line in enumerate(lines):
        if i in lines_to_delete:
            removed_any_line = True
            continue
        elif i in lines_to_rewrite:
            # Only count as change if rewrite is different from original
            if lines[i] != lines_to_rewrite[i]:
                removed_any_line = True
            new_lines.append(lines_to_rewrite[i])
        else:
            # Adjust comma logic might need refinement if disabled items affect it
            # Current logic: adjust comma if the *next kept non-deleted* line is ')'
            # This should still work correctly even with disabled items kept.
            is_multi_item_line = MULTI_IMPORT_ITEM_RE.match(line) is not None
            is_comment_line = line.strip().startswith("//")

            # Don't modify comment lines unless they are directly preceding a deleted line
            # (This case is tricky, let's keep the disable comment for now)
            # A simpler approach: never delete the disable comment itself.
            if is_comment_line and line.strip() == DISABLE_LINT_COMMENT:
                # Keep the disable comment always
                new_lines.append(line)
                continue

            if is_multi_item_line:
                # Check if the *next* kept line is the end parenthesis
                is_last_kept_item = False
                for j in range(i + 1, len(lines)):
                    # Consider lines that are *not* deleted and *not* just disable comments
                    is_potentially_kept = (
                        j not in lines_to_delete
                        and (
                            j not in lines_to_rewrite or lines[j] != lines_to_rewrite[j]
                        )
                        and lines[j].strip() != DISABLE_LINT_COMMENT
                    )
                    # Check if the potentially kept line is the closing parenthesis
                    if is_potentially_kept and MULTI_IMPORT_END_RE.match(lines[j]):
                        is_last_kept_item = True
                        break
                    # If we hit another item line or something else significant first, it's not the last
                    elif is_potentially_kept and not MULTI_IMPORT_END_RE.match(
                        lines[j]
                    ):
                        break

                if is_last_kept_item and line.strip().endswith(","):
                    new_lines.append(line.rstrip().rstrip(","))  # Remove trailing comma
                    if line != new_lines[-1]:
                        removed_any_line = True  # Count comma removal as change
                else:
                    new_lines.append(
                        line
                    )  # Keep line as is (or with comma if not last)

            else:
                new_lines.append(line)

    # Add trailing newline if original file had one and the new content doesn't
    new_content = "\n".join(new_lines)
    if original_content.endswith("\n") and not new_content.endswith("\n"):
        new_content += "\n"
    elif (
        not original_content.endswith("\n")
        and new_content.endswith("\n")
        and new_content != "\n"
    ):
        new_content = new_content.rstrip("\n")

    # Only return content if it actually changed OR if lines were marked for deletion
    # (even if the final string representation is identical due to whitespace nuances)
    if new_content != original_content or removed_any_line:
        # A final check: did we only remove comments? If so, no functional change.
        # This is hard to check perfectly, so we rely on string comparison primarily.
        # If removed_any_line is true, assume a change occurred.
        if new_content == original_content and not removed_any_line:
            return None  # No effective change
        # --- Cairo-format step ---
        try:
            # Re-format the file after modifications
            ast = parse_file(new_content, str(file_path))
            formatted_content = ast.format()
            return formatted_content
        except Exception as e:
            console.print(f"[red]Cairo-formatting failed for {file_path}: {e}[/]")
            return new_content  # Fallback: return unformatted but linted content
    else:
        return None


# (No changes needed in find_cairo_files, format command, or main block)
# find_identifier_usages also remains unchanged.


def find_identifier_usages(identifier: str, code_body: str) -> int:
    """Counts usages of an identifier in the code body using word boundaries."""
    pattern = r"\b" + re.escape(identifier) + r"\b"
    return len(re.findall(pattern, code_body))


def find_cairo_files(paths: List[Path]) -> List[Path]:
    """Recursively find all .cairo files in the given paths."""
    cairo_files = []

    # Load exclude directories from pyproject.toml if it exists
    exclude_dirs = []
    try:
        # Find pyproject.toml by searching up from the current directory
        root_dir = Path.cwd()
        pyproject_path = None

        # Try to find pyproject.toml by walking up directories
        current = root_dir
        while current != current.parent:
            candidate = current / "pyproject.toml"
            if candidate.exists():
                pyproject_path = candidate
                break
            current = current.parent

        if pyproject_path:
            pyproject = toml.load(pyproject_path)
            if "tool" in pyproject and "cairo-lint" in pyproject["tool"]:
                if "exclude_dirs" in pyproject["tool"]["cairo-lint"]:
                    exclude_dirs = [
                        os.path.normpath(os.path.join(pyproject_path.parent, d))
                        for d in pyproject["tool"]["cairo-lint"]["exclude_dirs"]
                    ]
                    console.print(f"[blue]Excluding directories: {exclude_dirs}[/]")
    except Exception as e:
        console.print(
            f"[yellow]Warning: Failed to load exclude_dirs from pyproject.toml: {e}[/]"
        )

    for path in paths:
        if path.is_file():
            if path.suffix == ".cairo":
                cairo_files.append(path)
            else:
                console.print(f"[yellow]Warning: Skipping non-Cairo file: {path}[/]")
        elif path.is_dir():
            for root, dirs, files in os.walk(path):
                root_path = Path(root)

                # Skip excluded directories
                if any(
                    os.path.normpath(str(root_path)).startswith(excluded)
                    for excluded in exclude_dirs
                ):
                    dirs[:] = []  # Skip all subdirectories
                    continue

                for file in files:
                    if file.endswith(".cairo"):
                        cairo_files.append(root_path / file)
        else:
            console.print(f"[yellow]Warning: Path not found: {path}[/]")
    return cairo_files


def _check_formatting(cairo_files: List[Path]) -> bool:
    """Check Cairo files for formatting issues without writing changes.
    Returns True if all files are correctly formatted, False otherwise.
    """
    checked_files = 0
    needs_formatting = []

    with console.status(f"[bold green]Checking {len(cairo_files)} files..."):
        for file_path in cairo_files:
            checked_files += 1
            new_content = process_file(file_path)

            if new_content is not None:
                needs_formatting.append(file_path)
                console.print(f"[yellow]Would reformat: {file_path}[/]")

    # --- Summary ---
    console.print("\n--- Summary ---")
    console.print(f"Checked {checked_files} files.")
    if needs_formatting:
        console.print(f"[bold yellow]{len(needs_formatting)} files need formatting.[/]")
        return False
    else:
        console.print("[bold green]All files are correctly formatted.[/]")
        return True


def _emit_formatting(cairo_files: List[Path]) -> None:
    """Process Cairo files and emit the formatted content to stdout."""
    for file_path in cairo_files:
        new_content = process_file(file_path)
        emitted_output = new_content if new_content else file_path.read_text().strip()
        print(emitted_output)


def _format_normal(cairo_files: List[Path]) -> None:
    """Format Cairo files and write changes to disk."""
    checked_files = 0
    changed_files = 0

    with console.status(f"[bold green]Formatting {len(cairo_files)} files..."):
        for file_path in cairo_files:
            checked_files += 1
            new_content = process_file(file_path)

            if new_content is not None:
                try:
                    file_path.write_text(new_content)
                    changed_files += 1
                    console.print(f"[blue]Reformatted: {file_path}[/]")
                except Exception as e:
                    console.print(f"[red]Error writing file {file_path}: {e}[/]")

    # --- Summary ---
    console.print("\n--- Summary ---")
    console.print(f"Checked {checked_files} files.")
    if changed_files > 0:
        console.print(f"[bold blue]{changed_files} files reformatted.[/]")
    else:
        console.print("[bold green]No files needed formatting.[/]")


@app.command()
def format(
    paths: List[Path] = typer.Argument(
        ...,
        help="One or more paths (files or directories) to format.",
        exists=True,
        resolve_path=True,
    ),
    check: bool = typer.Option(
        False,
        "--check",
        help="Check for formatting issues without writing changes.",
    ),
    emit: bool = typer.Option(
        None,
        "--emit",
        "-e",
        help="Emit the formatted file to stdout",
    ),
):
    """
    Formats Cairo files by removing unused imports.
    Respects `// cairo-lint: disable` comments on preceding lines.
    """
    cairo_files = find_cairo_files(paths)
    if not cairo_files:
        console.print("[yellow]No Cairo files found in the specified paths.[/]")
        raise typer.Exit()

    if check:
        all_formatted = _check_formatting(cairo_files)
        if not all_formatted:
            raise typer.Exit(code=1)
    elif emit:
        _emit_formatting(cairo_files)
    else:
        _format_normal(cairo_files)


if __name__ == "__main__":
    app()
