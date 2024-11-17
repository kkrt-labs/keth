from tests.utils.models import Block


class TestOs:

    def test_os(self, cairo_run, block, state):
        cairo_run("test_os", block=block, state=state)

    def test_block_hint(self, cairo_run, block: Block):
        output = cairo_run("test_block_hint", block=block)
        block_header = block.block_header

        assert output == [
            block_header.parent_hash_low,
            block_header.parent_hash_high,
            block_header.uncle_hash_low,
            block_header.uncle_hash_high,
            block_header.coinbase,
            block_header.state_root_low,
            block_header.state_root_high,
            block_header.transactions_trie_low,
            block_header.transactions_trie_high,
            block_header.receipt_trie_low,
            block_header.receipt_trie_high,
            block_header.withdrawals_root_is_some,
            *block_header.withdrawals_root_value,
            *block_header.bloom,
            block_header.difficulty_low,
            block_header.difficulty_high,
            block_header.number,
            block_header.gas_limit,
            block_header.gas_used,
            block_header.timestamp,
            block_header.mix_hash_low,
            block_header.mix_hash_high,
            block_header.nonce,
            block_header.base_fee_per_gas_is_some,
            block_header.base_fee_per_gas_value,
            block_header.blob_gas_used_is_some,
            block_header.blob_gas_used_value,
            block_header.excess_blob_gas_is_some,
            block_header.excess_blob_gas_value,
            block_header.parent_beacon_block_root_is_some,
            *block_header.parent_beacon_block_root_value,
            block_header.requests_root_is_some,
            *block_header.requests_root_value,
            block_header.extra_data_len,
            *[int(byte) for byte in block_header.extra_data],
        ]
