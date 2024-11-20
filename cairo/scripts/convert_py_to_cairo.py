"""
Convert Python files to Cairo code

Usage:
    python convert_py_to_cairo.py ethereum/cancun/vm/gas.py

    --dry-run: Print the output instead of writing to file

Note: This script is not fully compatible with all Python code. It's AI generated code.
Use this as a starting point and manually adjust the generated code.
"""

import argparse
import ast
import os
import site
from pathlib import Path
from typing import List, Optional


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


class CairoConverter(ast.NodeVisitor):
    def __init__(self, file_path: str):
        self.file_path = file_path
        self.imports: List[str] = []
        self.constants: List[str] = []
        self.structs: List[str] = []
        self.functions: List[str] = []
        self.current_module_parts = self._get_module_parts()
        self.indentation = "    "

    def _get_module_parts(self) -> List[str]:
        """Get the module path parts relative to ethereum"""
        parts = Path(self.file_path).parts
        try:
            eth_index = parts.index("ethereum")
            return list(parts[eth_index:-1])  # Exclude the filename
        except ValueError:
            print(f"Error: Could not find 'ethereum' in path: {self.file_path}")
            return []

    def convert(self, content: str) -> str:
        """Convert Python content to Cairo code"""
        tree = ast.parse(content)
        self.visit(tree)

        # Combine all parts in the correct order
        result = []
        if self.imports:
            result.extend(self.imports)
            result.append("")
        if self.constants:
            result.extend(self.constants)
            result.append("")
        if self.structs:
            result.extend(self.structs)
            result.append("")
        if self.functions:
            result.extend(self.functions)

        return "\n".join(result)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        """Handle function definitions"""
        # Get return type annotation if it exists
        return_type = self._get_annotation(node.returns) if node.returns else None
        returns = f" -> {return_type}" if return_type else ""

        # Get parameters
        params = []
        for arg in node.args.args:
            if arg.annotation:
                param_type = self._get_annotation(arg.annotation)
                if param_type:
                    params.append(f"{arg.arg}: {param_type}")
            else:
                params.append(arg.arg)

        # Create function signature
        func_def = f"func {node.name}({', '.join(params)}){returns} {{"

        # Add function body with proper indentation
        body = []

        def process_node(node: ast.AST, indent_level: int = 1) -> List[str]:
            """Recursively process AST nodes and return commented lines"""
            lines = []
            indent = self.indentation * indent_level

            if isinstance(node, ast.Expr) and isinstance(node.value, ast.Str):
                return lines  # Skip docstrings

            # Always comment out the current node
            node_str = ast.unparse(node)
            if "\n" in node_str:
                # For multiline statements, comment each line
                for line in node_str.split("\n"):
                    if line.strip():  # Skip empty lines
                        lines.append(f"{indent}// {line.strip()}")
            else:
                lines.append(f"{indent}// {node_str}")

            # Process children for compound statements
            if isinstance(node, ast.If):
                for item in node.body:
                    lines.extend(process_node(item, indent_level + 1))
                if node.orelse:
                    lines.append(f"{indent}// else:")
                    for item in node.orelse:
                        lines.extend(process_node(item, indent_level + 1))
            elif isinstance(node, ast.For):
                for item in node.body:
                    lines.extend(process_node(item, indent_level + 1))
            elif isinstance(node, ast.While):
                for item in node.body:
                    lines.extend(process_node(item, indent_level + 1))
            elif isinstance(node, ast.Try):
                for item in node.body:
                    lines.extend(process_node(item, indent_level + 1))
                for handler in node.handlers:
                    if handler.type:
                        lines.append(f"{indent}// except {ast.unparse(handler.type)}:")
                    else:
                        lines.append(f"{indent}// except:")
                    for item in handler.body:
                        lines.extend(process_node(item, indent_level + 1))

            return lines

        # Process the function body
        body.append(f"{self.indentation}// Implementation:")
        for item in node.body:
            body.extend(process_node(item))

        # Close function
        body.append("}")
        body.append("")  # Add empty line after function

        self.functions.extend([func_def] + body)

    def visit_ImportFrom(self, node: ast.ImportFrom) -> None:
        """Handle from-imports"""
        if node.level > 0:  # Relative import
            # Calculate the target module
            if node.level == 1:  # from .
                module_parts = self.current_module_parts
            else:  # from ..
                module_parts = self.current_module_parts[: -node.level + 1]

            if node.module:
                module_parts = module_parts + [node.module]

            module_path = ".".join(module_parts)
        else:
            module_path = node.module

        # Only keep ethereum imports
        if module_path and module_path.startswith("ethereum"):
            import_names = ", ".join(name.name for name in node.names)
            self.imports.append(f"from {module_path} import {import_names}")

    def visit_Assign(self, node: ast.Assign) -> None:
        """Handle constant assignments"""
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id.isupper():
                value = self._convert_constant_value(node.value)
                if value is not None:
                    self.constants.append(f"const {target.id} = {value};")

    def _convert_constant_value(self, node: ast.expr) -> Optional[str]:
        """Convert constant values to Cairo syntax"""
        if isinstance(node, ast.Num):
            return str(node.n)
        elif isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                if node.func.id in ("Uint", "U64"):
                    if len(node.args) == 1:
                        return self._convert_constant_value(node.args[0])
        elif isinstance(node, ast.BinOp):
            if isinstance(node.op, ast.Pow):
                left = self._convert_constant_value(node.left)
                right = self._convert_constant_value(node.right)
                if left and right:
                    return f"{left}**{right}"
        return None

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        """Handle class definitions"""
        # Check if it's a dataclass
        if any(
            isinstance(dec, ast.Name)
            and dec.id == "dataclass"
            or isinstance(dec, ast.Call)
            and isinstance(dec.func, ast.Name)
            and dec.func.id == "dataclass"
            for dec in node.decorator_list
        ):
            fields = []
            for item in node.body:
                if isinstance(item, ast.AnnAssign) and isinstance(
                    item.target, ast.Name
                ):
                    field_type = self._get_annotation(item.annotation)
                    if field_type:
                        fields.append(f"    {item.target.id}: {field_type},")

            if fields:
                struct_def = [f"struct {node.name} {{", *fields, "}", ""]
                self.structs.extend(struct_def)

    def _get_annotation(self, node: ast.expr) -> Optional[str]:
        """Convert type annotations to Cairo types"""
        if isinstance(node, ast.Name):
            return node.id
        elif isinstance(node, ast.Subscript):
            # Handle generic types if needed
            return None
        return None


def create_cairo_file(relative_path: str, dry_run: bool = False):
    """
    Convert a Python file to a Cairo file with proper imports

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
    converter = CairoConverter(str(python_file))
    cairo_content = converter.convert(content)

    # Create the output path in cairo workdir
    try:
        eth_index = Path(relative_path).parts.index("ethereum")
        relative_parts = Path(relative_path).parts[eth_index:]
        output_path = Path(".") / "/".join(relative_parts)
        output_path = output_path.with_suffix(".cairo")

        if dry_run:
            print(f"Would create file: {output_path}")
            print("\nContent:")
            print("=" * 80)
            print(cairo_content)
            print("=" * 80)
        else:
            # Create directories if they don't exist
            os.makedirs(output_path.parent, exist_ok=True)

            # Write the Cairo file
            with open(output_path, "w") as f:
                f.write(cairo_content)
            print(f"Created Cairo file: {output_path}")
    except ValueError:
        print(f"Error: Path must contain 'ethereum': {relative_path}")


def main():
    parser = argparse.ArgumentParser(description="Convert Python files to Cairo")
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
    create_cairo_file(args.file, args.dry_run)


if __name__ == "__main__":
    main()
