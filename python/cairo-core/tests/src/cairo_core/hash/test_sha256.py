import hashlib

from hypothesis import given


class TestSha256:
    @given(buffer=...)
    def test_sha256_bytes(self, cairo_run, buffer: bytes):
        expected_hash = hashlib.sha256(buffer).digest()
        assert expected_hash == cairo_run("sha256_bytes", buffer)
