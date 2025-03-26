from ethereum.cancun.trie import bytes_to_nibble_list
from ethereum_types.bytes import Bytes
from hypothesis import given

from mpt.utils import nibble_list_to_bytes


class TestUtils:
    @given(bytes=...)
    def test_nibble_list_to_bytes(self, bytes: Bytes):
        assert nibble_list_to_bytes(bytes_to_nibble_list(bytes)) == bytes
