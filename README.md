# keth

Keth is an open-source, proving backend for Ethereum, Optimism, Arbitrum and
arbitrary Ethereum execution environments built with
[Kakarot Core EVM](https://github.com/kkrt-labs/kakarot) and
[Starkware's provable VM, Cairo](https://book.cairo-lang.org/) as well as
[Reth ExEx](https://www.paradigm.xyz/2024/05/reth-exex).

Similar to [zeth](https://github.com/kkrt-labs/keth/edit/main/README.md), keth
makes it possible to prove a given block by completing all the necessary steps
required to assert its integrity in the provable Cairo Virtual Machine:

- verify transactions validity (signature, sufficient balance & nonce);
- execute transactions in the block;
- verify storage reads and writes;
- paying block rewards;
- update state root;
- compute transactions and receipts tries;
- compute the block hash;
- etc.

By running this process in the context of the Cairo VM, we can generate a STARK
proof that the new block is valid. For Optimism and Arbitrum, keth will draw
inspiration from zeth and its ability to ensure that the block was correctly
derived from the available data posted to Ethereum.

## Status

Keth is a work in progress (WIP ⚠️) and as such is not suitable for production.

## Architecture Diagram

Coming soon 🏗️.

## Acknowledgements

- zeth: inspiration and design is drawn from Risc-Zero's
  [zeth](https://github.com/risc0/zeth). We warmly thank the team for their
  openness and cutting-edge research on the subject of Type 1 provers.
- reth: keth's backend logic relies on
  [Reth Execution Extensions](https://www.paradigm.xyz/2024/05/reth-exex). Thank
  you to the team who have helped us since day 1 in design and development.
- Herodotus: keth's Cairo code relies on Herodotus' implementation and
  architecture of MPT proofs in Cairo. Thank you to the team who have helped in
  designing our Cairo code and development.
