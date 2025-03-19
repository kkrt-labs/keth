# Ethereum MPT Library

A Python library for working with Ethereum's Merkle Patricia Tries (MPT).

## Overview

This library provides the ability to:

- ✅ derive Ethereum partial state tries from
  [prover inputs](https://github.com/kkrt-labs/zk-pig).
- ⌛ transform an Ethereum partial state trie into an
  [EELS](https://github.com/ethereum/execution-specs/tree/master/src/ethereum/cancun)
  `State` object
- ⌛ compute the difference between two Ethereum partial state tries

## Quick Start

```python
from pathlib import Path

from mpt.ethereum_tries import EthereumTries

# Load tries from a JSON dump
tries = EthereumTries.from_json(Path("data/1/inputs/22074629.json"))
```

## Example input

```json
{
  "version": "",
  "blocks": [
    {
      "header": {
        "parentHash": "0x0cb00576a2ea1e7b93d8f352dd020903900c8d9ed04bb5a984122fa8f3a06393",
        "sha3Uncles": "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
        "miner": "0x4838b106fce9647bdf1e7877bf73ce8b0bad5f97",
        "stateRoot": "0x62d50cde3c655666aa53427e4425c4d3d8e9c4ecd495a5b497f863f777fe878d",
        "transactionsRoot": "0x6c9b1e0e2005824276589b27935b86563e5904e5bb265f1d613158dd905fc96d",
        "receiptsRoot": "0x26b06a76c1b7bd2db6ef7b03cfe66787af33586c46f6abf3d035529ba6ee6c73",
        "logsBloom": "0xa529da2e711b08501b8b38f8caba398f00e944e14c7b8f353fb9c60e36138cceae1439affd198142081c5bca26a6c5ec0e3b190d4ce3382c20817d89302f01a7d744cbaa00520abeb8424d2a0c5e11f9668060f30644cc6d4dd04f67aa61a8859703040fb3eb22ea8186c70d2a9afb89b65208a035180d075c98c596894bcd3db64102fec56145096b5a730a472024ae1e650807e994d68c502aad44a0ff508b1b43276184b9e9d2175097e039c62e06455ee7089dd54154c9eee7550ccb01708a966d2bcb39cb525b81a6fac3221c0908e4e356f78005790cf6034a0bcb628286b1edf82541f56311649a8862074ab60c70c8a0e7ac31d13829d54a62b7f6c0",
        "difficulty": "0x0",
        "number": "0x150b207",
        "gasLimit": "0x224c7ad",
        "gasUsed": "0xa77f76",
        "timestamp": "0x67d7e91b",
        "extraData": "0x546974616e2028746974616e6275696c6465722e78797a29",
        "mixHash": "0x820b36c8571d9e4745f6401bc0be4289e94bc63fad29e04225298fa7eb631570",
        "nonce": "0x0000000000000000",
        "baseFeePerGas": "0x1b401248",
        "withdrawalsRoot": "0x9a0a49dc079daed61f66ea8837e87f823ebe144e30b526f700bc5f1a8e37470a",
        "blobGasUsed": "0x40000",
        "excessBlobGas": "0x3a40000",
        "parentBeaconBlockRoot": "0x6dd1f4dd61d0b73f782d01592d0c7fbfad7ece2e3ef2752a87ccc5a1c1da056a",
        "requestsRoot": null,
        "hash": "0x4de0866e8f5e6545c45f90ae5ccffd6ba6bf19a8556e75b147ce1d9570a7561f"
      },
      "transaction": [
        {
          "type": "0x2",
          "chainId": "0x1",
          "nonce": "0x1a6e",
          "to": "0x04ce218ead72401702dd5f3e56cedb7d2d477777",
          "gas": "0x10c8e0",
          "gasPrice": null,
          "maxPriorityFeePerGas": "0x3b9aca00",
          "maxFeePerGas": "0xb2d05e00",
          "value": "0x14de69831cd16b",
          "input": "0x295f0582000000",
          "accessList": [],
          "v": "0x0",
          "r": "0xc9fa8fad095ae48290fc4959056e519635246d81c89483dab0ff7038fdd564c9",
          "s": "0x4186bb8042dfd12ee32a1d944c951bc5178708a9b9aa579237a7f53f934c8110",
          "yParity": "0x0",
          "hash": "0xa52e1231a80cc7094ef8b80d83a66d7b6beb3605854524c42e3ab74a76be3079"
        },
        {
          "type": "0x2",
          "chainId": "0x1",
          "nonce": "0xe328c",
          "to": "0xfbd4cdb413e45a52e2c8312f670e9ce67e794c37",
          "gas": "0x3e354",
          "gasPrice": null,
          "maxPriorityFeePerGas": "0xc7c2f688",
          "maxFeePerGas": "0xe30308d0",
          "value": "0x150b207",
          "input": "0xa00000000000000000000000000000007c706586679af2ba6d1a9fc2da9c6af59883fdd3000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000055959fad020000000000000000000000000000000000000000000000000a624f43ea61c8f3000000000000000000000000e0f63a424a4439cbe457d80e4f4b51ad25b2c56c",
          "accessList": [],
          "v": "0x0",
          "r": "0x98883e8f2d9bfcc346d9d80f69dbb55060694b0400188f7cc8cb14b9b538bd99",
          "s": "0x512aeb6337412f71f59627959f0babfd8ac2f4b68222c49d18cf79b52a5cc3bf",
          "yParity": "0x0",
          "hash": "0x9fb76339174b8d0cd929f1652249e4e106f8e94a67f55e4ecd2b506301ec1886"
        }
      ]
    }
  ],
  "witness": {
    "state": [
      "0xf90211a033df1410f47dbe69eeb36d1a7167a86e606b6d49b7bf6d78e254e78af2fcb4e8a02a63c4e3717"
    ],
    "ancestors": [
      {
        "parentHash": "0xcdbfe5ba6bb8199db55ce3932a6938d38a18e5f1b2ee5e9c975ce0cc869f7ae2",
        "sha3Uncles": "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
        "miner": "0x95222290dd7278aa3ddd389cc1e1d165cc4bafe5",
        "stateRoot": "0x79975703bf7aa84107288742ae58c79f0b1a3c4f283ff9f2fc7661fe87c323d6",
        "transactionsRoot": "0xc56e5f245e3f371328f65af96f664fa9b687d5d5d653577792ecf80e2368d00c",
        "receiptsRoot": "0x9fca8cc579f5e36353ddcea967870790e8a555f42cc85c74539cd8fa14fd62dc",
        "logsBloom": "0xa9e537c70e3dd59ea6564c35a219fce901d3e13db75a4d1d035f6945987ba0f33df3e8aef29dea981cd2a1bd69bfe5367f6777bcdc9679606787d53f01b2ec86cf94c5dcd2dbda9aea62f93f767420f35e4f75fb11f7bb69450f4eff8f7863e95ae745ecfaf6adfcb1a1dd9c0d1ead82e4532f2d96989fdaf5cc5d7e00edd75976425f1e25ebf398e4f1db5b2f86e8ad9c6d0e396ff18a3f9d29a8e7e5f797f9eecbf97681976f348ef7fdb692f307ea61ff8475dbe06287d376f64e3997f9f5fdc36c9e6ec91b503bc2f0920579fda7bddfecf7e76e205bdc77f32fb766b5d2bb92e66aa0453c366ad4330be7d948a2f74d56984d6eed544b8599228b546561",
        "difficulty": "0x0",
        "number": "0x150b206",
        "gasLimit": "0x2255100",
        "gasUsed": "0x2251c86",
        "timestamp": "0x67d7e90f",
        "extraData": "0x6265617665726275696c642e6f7267",
        "mixHash": "0xdb620a61ac78b56302b2bd9974c8188e4facb2d747fbf724e4b765decc05e456",
        "nonce": "0x0000000000000000",
        "baseFeePerGas": "0x18397775",
        "withdrawalsRoot": "0xb8d769aa5099f9b8151aaf55f38b7ad3489badbd831c0017dcf8759169db462b",
        "blobGasUsed": "0xc0000",
        "excessBlobGas": "0x39e0000",
        "parentBeaconBlockRoot": "0xd978644fd64ba36ed882baf79a0bd88daa39002c0df037e9b6ce2a02ff8ed8b4",
        "requestsRoot": null,
        "hash": "0x0cb00576a2ea1e7b93d8f352dd020903900c8d9ed04bb5a984122fa8f3a06393"
      }
    ],
    "codes": ["0x608060405234801561000f575f80fd5b50600436106100ad575f3560e01c"]
  },
  "chainConfig": {
    "chainId": 1,
    "homesteadBlock": 1150000,
    "daoForkBlock": 1920000,
    "daoForkSupport": true,
    "eip150Block": 2463000,
    "eip155Block": 2675000,
    "eip158Block": 2675000,
    "byzantiumBlock": 4370000,
    "constantinopleBlock": 7280000,
    "petersburgBlock": 7280000,
    "istanbulBlock": 9069000,
    "muirGlacierBlock": 9200000,
    "berlinBlock": 12244000,
    "londonBlock": 12965000,
    "arrowGlacierBlock": 13773000,
    "grayGlacierBlock": 15050000,
    "shanghaiTime": 1681338455,
    "cancunTime": 1710338135,
    "terminalTotalDifficulty": 58750000000000000000000,
    "depositContractAddress": "0x00000000219ab540356cbb839cbe05303d7705fa",
    "ethash": {}
  },
  "accessList": [
    {
      "address": "0xda1953ad71dbc34eb225092da21ca8ef53f4c9a1",
      "storageKeys": [
        "0x0000000000000000000000000000000000000000000000000000000000000000"
      ]
    },
    {
      "address": "0xb7486b5bd2d14714950b082eafebe9822a1d96ee",
      "storageKeys": null
    },
    {
      "address": "0xf76f55e7e0ebbeb18e87af665529b7ebed4fbd32",
      "storageKeys": null
    }
  ]
}
```

## License

MIT
