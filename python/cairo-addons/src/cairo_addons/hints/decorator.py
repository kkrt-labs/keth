import ast
import inspect

implementations = {}


def get_function_body(func) -> str:
    """Extract just the body of a function as a string."""
    source = inspect.getsource(func)

    # Parse the source into an AST
    tree = ast.parse(source)

    # Get the function definition node
    func_def = tree.body[0]

    # Split source into lines
    lines = source.splitlines()

    # Handle single-line functions (body on same line as def)
    if len(func_def.body) == 1 and isinstance(func_def.body[0], ast.Expr):
        body = str(func_def.body[0].value.value)  # For docstrings
    # Handle single-line functions with return/assign/etc
    elif len(lines) <= func_def.body[0].lineno:
        body_lines = [lines[-1]]  # Take last line as body
        indent = len(body_lines[0]) - len(body_lines[0].lstrip())
        body = body_lines[0][indent:]
    else:
        # Multi-line function - get all non-empty lines after def
        body_lines = [
            line for line in lines[func_def.body[0].lineno - 1 :] if line != ""
        ]
        if body_lines:
            indent = len(body_lines[0]) - len(body_lines[0].lstrip())
            body = "\n".join(line[indent:] for line in body_lines)
        else:
            body = "pass"  # Empty function body

    return body


def register_hint(wrapped_function):
    implementations[wrapped_function.__name__] = get_function_body(wrapped_function)

    return wrapped_function
