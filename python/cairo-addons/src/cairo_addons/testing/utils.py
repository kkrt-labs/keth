from typing import Iterable


def flatten(data):
    result = []

    def _flatten(item):
        if isinstance(item, Iterable) and not isinstance(item, (str, bytes, bytearray)):
            for sub_item in item:
                _flatten(sub_item)
        else:
            result.append(item)

    _flatten(data)
    return result
