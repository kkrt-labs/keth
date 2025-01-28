from typing import Tuple

from hypothesis import given

from ethereum.cancun.blocks import Log
from ethereum.cancun.bloom import add_to_bloom, logs_bloom
from tests.utils.args_gen import MutableBloom


class TestBloom:
    @given(bloom=..., bloom_entry=...)
    def test_add_to_bloom(self, cairo_run, bloom: MutableBloom, bloom_entry: bytes):
        cairo_bloom = cairo_run("add_to_bloom", bloom, bloom_entry)
        add_to_bloom(bloom, bloom_entry)
        assert cairo_bloom == bloom

    @given(logs=...)
    def test_logs_bloom(self, cairo_run, logs: Tuple[Log, ...]):
        cairo_bloom = cairo_run("logs_bloom", logs)
        bloom = logs_bloom(logs)
        print([hex(b) for b in bloom])
        assert cairo_bloom == bloom
