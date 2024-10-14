from starkware.cairo.common.uint256 import Uint256

namespace ICairo1Helpers {
    func exec_precompile(address: felt, data_len: felt, data: felt*) -> (
        success: felt, gas: felt, return_data_len: felt, return_data: felt*
    ) {
    }

    func get_block_hash(block_number: felt) -> (hash: felt) {
        return (hash=0);
    }

    func recover_eth_address(msg_hash: Uint256, r: Uint256, s: Uint256, y_parity: felt) -> (
        success: felt, address: felt
    ) {
        // TODO: Implement this function.
        return (0, 0);
    }

    func verify_signature_secp256r1(
        msg_hash: Uint256, r: Uint256, s: Uint256, x: Uint256, y: Uint256
    ) -> (is_valid: felt) {
    }
}

namespace IAccount {
    func is_valid_jumpdest(address: felt, index: felt) -> (is_valid: felt) {
    }
}
