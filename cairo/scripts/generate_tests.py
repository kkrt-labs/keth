"""
Generate test files for Python files

Usage:
    python generate_tests.py ethereum/cancun/vm/gas.py

    --dry-run: Print the output instead of writing to file

Note: This script is not fully compatible with all Python code. It's AI generated code.
Use this as a starting point and manually adjust the generated code.
"""

import argparse
import ast
import os
import site
from pathlib import Path
from typing import List, Optional, Set


def get_site_packages_path() -> Path:
    """Get the site-packages directory of the current Python interpreter"""
    return Path(site.getsitepackages()[0])


def resolve_ethereum_path(relative_path: str) -> Path:
    """
    Convert a path relative to ethereum to a full path in site-packages

    Example: ethereum/cancun/vm/gas.py -> /path/to/site-packages/ethereum/cancun/vm/gas.py
    """
    site_packages = get_site_packages_path()
    return site_packages / relative_path


class TestGenerator(ast.NodeVisitor):
    def __init__(self, file_path: str, source_content: str):
        self.file_path = file_path
        self.source_content = source_content
        self.class_name = self._get_class_name()
        self.test_functions: List[str] = []
        self.imports: Set[str] = set()
        self.functions_to_import: Set[str] = set()
        self.current_function: Optional[str] = None

    def _get_class_name(self) -> str:
        """Get the test class name from the file name"""
        file_name = Path(self.file_path).stem
        return f"Test{file_name.title()}"

    def _get_annotation(self, node: ast.expr) -> Optional[str]:
        """Convert type annotations to Cairo types"""
        if isinstance(node, ast.Name):
            return node.id
        elif isinstance(node, ast.Subscript):
            # Handle generic types like List[T], Tuple[T, ...], etc.
            if isinstance(node.value, ast.Name):
                value_type = node.value.id
                if value_type in ("List", "Tuple"):
                    # Add typing imports
                    self.imports.add("from typing import List, Tuple")

                    if isinstance(node.slice, ast.Name):
                        return f"{value_type}[{node.slice.id}]"
                    elif isinstance(node.slice, ast.Tuple):
                        slice_types = []
                        for elt in node.slice.elts:
                            if isinstance(elt, ast.Name):
                                slice_types.append(elt.id)
                        return f"{value_type}[{', '.join(slice_types)}]"
                    elif isinstance(node.slice, ast.Subscript):
                        # Handle nested types like List[Tuple[U256, U256]]
                        inner_type = self._get_annotation(node.slice)
                        if inner_type:
                            return f"{value_type}[{inner_type}]"
        return None

    def convert(self, content: str) -> str:
        """Convert Python content to test file"""
        tree = ast.parse(content)
        self.visit(tree)

        # Combine all parts
        result = [
            "from hypothesis import given",
            "from hypothesis import strategies as st",
        ]

        # Add imports from source file
        if self.imports:
            result.extend(sorted(self.imports))

        # Add function imports if needed
        if self.functions_to_import:
            result.append(
                f"from {'.'.join(self._get_module_parts())} import {', '.join(sorted(self.functions_to_import))}"
            )

        result.extend(["", f"class {self.class_name}:"])

        if self.test_functions:
            result.extend(self.test_functions)

        return "\n".join(result)

    def _get_module_parts(self) -> List[str]:
        """Get the module path parts relative to ethereum"""
        parts = Path(self.file_path).parts
        try:
            eth_index = parts.index("ethereum")
            # Remove .py extension from the filename before including it
            path_parts = list(parts[eth_index:-1])  # Get directory parts
            file_name = Path(parts[-1]).stem  # Get filename without extension
            return path_parts + [file_name]
        except ValueError:
            print(f"Error: Could not find 'ethereum' in path: {self.file_path}")
            return []

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        """Collect imports from the source file"""
        if node.level > 0:  # Relative import
            # Calculate the target module
            module_parts = self._get_module_parts()[:-1]  # Exclude filename
            if node.level == 1:  # from .
                pass
            else:  # from ..
                module_parts = module_parts[: -node.level + 1]

            if node.module:
                module_parts = module_parts + [node.module]

            module_path = ".".join(["ethereum"] + module_parts[1:])
        else:
            module_path = node.module

        # Only keep ethereum imports
        if module_path and module_path.startswith("ethereum"):
            import_str = f"from {module_path} import {', '.join(name.name for name in node.names)}"
            self.imports.add(import_str)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        """Handle function definitions"""
        # Skip if it's a private function or special method
        if node.name.startswith("_"):
            return

        # Store current function name
        self.current_function = node.name

        # Add function to imports
        self.functions_to_import.add(node.name)

        # Get parameters
        params = []
        param_types = []

        # Add cairo_run as first parameter
        params.append("self")
        params.append("cairo_run")

        # Process other parameters
        given_args = []

        # Find the original function in the AST
        original_func = None
        for n in ast.walk(ast.parse(self.source_content)):
            if isinstance(n, ast.FunctionDef) and n.name == self.current_function:
                original_func = n
                break

        if original_func:
            # Process parameters from the original function
            for arg in original_func.args.args:
                params.append(arg.arg)
                if arg.annotation:
                    param_type = self._get_annotation(arg.annotation)
                    if param_type:
                        param_types.append(f"{arg.arg}: {param_type}")
                        given_args.append(f"{arg.arg}=...")
                        # Add any imports needed for type annotations
                        self._add_type_imports(arg.annotation)

        # Create test function
        func_lines = []

        # Add single @given decorator with all parameters
        if given_args:
            func_lines.append(f"    @given({', '.join(given_args)})")

        # Add function definition with type annotations
        if param_types:
            type_annotations = ", ".join(["self", "cairo_run", *param_types])
            func_def = f"    def test_{self.current_function}({type_annotations}):"
        else:
            func_def = f"    def test_{self.current_function}({', '.join(params)}):"

        # Add function body
        args_str = ", ".join(arg for arg in params[2:])  # Skip self and cairo_run
        func_body = f'        assert {self.current_function}({args_str}) == cairo_run("{self.current_function}", {args_str})'

        func_lines.extend([func_def, func_body, ""])

        self.test_functions.extend(func_lines)

    def _add_type_imports(self, node: ast.AST) -> None:
        """Add imports needed for type annotations"""
        if isinstance(node, ast.Name):
            # Add basic types to imports if they're from ethereum
            if node.id in {"U256", "U64", "Uint", "Bytes", "Bytes32"}:
                self.imports.add("from ethereum.base_types import " + node.id)
        elif isinstance(node, ast.Subscript):
            # Handle generic types
            if isinstance(node.value, ast.Name):
                # Add container types like List, Tuple, etc.
                if node.value.id in ("List", "Tuple"):
                    self.imports.add("from typing import List, Tuple")
                    # Process inner types recursively
                    if isinstance(node.slice, ast.Name):
                        self._add_type_imports(node.slice)
                    elif isinstance(node.slice, ast.Tuple):
                        for elt in node.slice.elts:
                            self._add_type_imports(elt)
                    elif isinstance(node.slice, ast.Subscript):
                        self._add_type_imports(node.slice)


def create_test_file(relative_path: str, dry_run: bool = False):
    """
    Create a test file for a Python file

    Parameters
    ----------
    relative_path : str
        Path relative to ethereum module (e.g., "ethereum/cancun/vm/gas.py")
    dry_run : bool
        If True, print the output instead of writing to file
    """
    # Get the full path in site-packages
    python_file = resolve_ethereum_path(relative_path)

    if not python_file.exists():
        print(f"Error: File not found: {python_file}")
        return

    # Read the Python file
    with open(python_file, "r") as f:
        content = f.read()

    # Convert the content
    generator = TestGenerator(str(python_file), content)
    test_content = generator.convert(content)

    # Create the output path in cairo/tests directory
    try:
        eth_index = Path(relative_path).parts.index("ethereum")
        relative_parts = Path(relative_path).parts[eth_index:]
        # Create test file path
        output_path = Path("tests") / "/".join(relative_parts)
        output_path = output_path.parent / f"test_{output_path.name}"

        if dry_run:
            print(f"Would create file: {output_path}")
            print("\nContent:")
            print("=" * 80)
            print(test_content)
            print("=" * 80)
        else:
            # Create directories if they don't exist
            os.makedirs(output_path.parent, exist_ok=True)

            # Write the test file
            with open(output_path, "w") as f:
                f.write(test_content)
            print(f"Created test file: {output_path}")
    except ValueError:
        print(f"Error: Path must contain 'ethereum': {relative_path}")


def main():
    parser = argparse.ArgumentParser(description="Generate test files for Python files")
    parser.add_argument(
        "file",
        help="Path relative to ethereum module (e.g., 'ethereum/cancun/vm/gas.py')",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the output instead of writing to file",
    )

    args = parser.parse_args()
    create_test_file(args.file, args.dry_run)


if __name__ == "__main__":
    main()
