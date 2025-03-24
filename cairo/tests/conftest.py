from dataclasses import fields

from dotenv import load_dotenv

load_dotenv()


def pytest_assertrepr_compare(op, left, right):
    """
    Custom assertion comparison for EVM objects to provide detailed field-by-field comparison.
    """
    if not (
        hasattr(left, "__class__")
        and hasattr(right, "__class__")
        and left.__class__.__name__ == "Evm"
        and right.__class__.__name__ == "Evm"
        and op == "=="
    ):
        return None

    lines = []
    for field in fields(left):
        left_val = getattr(left, field.name)
        right_val = getattr(right, field.name)

        if field.name != "error":
            # Regular field comparison
            if left_val != right_val:
                lines.extend(
                    [
                        f"{field.name} field mismatch:",
                        f"  left:  {left_val}",
                        f"  right: {right_val}",
                    ]
                )
        else:
            if left_val is not None and str(left_val) != str(right_val):
                lines.extend(
                    [
                        "error field mismatch:",
                        f"  left:  {left_val}",
                        f"  right: {right_val}",
                    ]
                )
            elif not isinstance(left_val, type(right_val)):
                lines.extend(
                    [
                        "error field mismatch:",
                        f"  left:  {type(left_val)}",
                        f"  right: {type(right_val)}",
                    ]
                )

    return lines if len(lines) > 0 else None
