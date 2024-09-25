import pytest

from tests.utils.models import BlockHeader


@pytest.fixture
def block_header():
    return BlockHeader.model_validate(
        {
            "baseFeePerGas": "0x0a",
            "blobGasUsed": "0x00",
            "bloom": "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            "coinbase": "0x2adc25665018aa1fe0e6bc666dac8fc2697ff9ba",
            "difficulty": "0x00",
            "excessBlobGas": "0x00",
            "extraData": "0x00",
            "gasLimit": "0x0f4240",
            "gasUsed": "0x0156f8",
            "hash": "0x46e317ac1d4c1a14323d9ef994c0f0813c6a90af87113a872ca6bcfcea86edba",
            "mixHash": "0x0000000000000000000000000000000000000000000000000000000000020000",
            "nonce": "0x0000000000000000",
            "number": "0x01",
            "parentBeaconBlockRoot": "0x0000000000000000000000000000000000000000000000000000000000000000",
            "parentHash": "0x02a4bfb03275efd1bf926bcbccc1c12ef1ed723414c1196b75c33219355c7180",
            "receiptTrie": "0xf44202824894394d28fa6c8c8e3ef83e1adf05405da06240c2ce9ca461e843d1",
            "stateRoot": "0x2f79dbc20b78bcd7a771a9eb6b25a4af69724085c97be69a95ba91187e66a9c0",
            "timestamp": "0x64903c57",
            "transactionsTrie": "0x5f3c4c1da4f0b2351fbb60b9e720d481ce0706b5aa697f10f28efbbab54e6ac8",
            "uncleHash": "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
            "withdrawalsRoot": "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
        }
    )


class TestOs:

    def test_os(self, cairo_run, block_header):
        cairo_run("test_os", block_header=block_header)

    def test_block_header(self, cairo_run, block_header):
        result = cairo_run("test_block_header", block_header=block_header)
        assert BlockHeader.model_validate(result) == block_header
