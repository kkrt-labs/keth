// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

/// @notice Contract for integration testing of EVM opcodes.
/// @author Kakarot9000
/// @dev Add functions and storage variables for opcodes accordingly.
contract PlainOpcodes {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event CreateAddress(address _address) anonymous;
    event Create2Address(address _address) anonymous;

    function create(bytes memory bytecode, uint256 count) public returns (address[] memory) {
        address[] memory addresses = new address[](count);
        address _address;
        for (uint256 i = 0; i < count; i++) {
            assembly {
                _address := create(0, add(bytecode, 32), mload(bytecode))
            }
            addresses[i] = _address;
            emit CreateAddress(_address);
        }
        return addresses;
    }

    function create2(bytes memory bytecode, uint256 salt) public returns (address _address) {
        assembly {
            _address := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        emit Create2Address(_address);
    }
}
