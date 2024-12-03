def sequence_equal(a, b) -> bool:
    """Compare sequences recursively, treating lists and tuples as equivalent"""
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        return len(a) == len(b) and all(sequence_equal(x, y) for x, y in zip(a, b))
    return a == b
