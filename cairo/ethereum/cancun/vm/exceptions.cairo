from ethereum.exceptions import EthereumException

// Revert
const Revert = 'Revert';

// Exceptional halt
const StackUnderflowError = 'StackUnderflowError';
const StackOverflowError = 'StackOverflowError';
const OutOfGasError = 'OutOfGasError';
const InvalidOpcode = 'InvalidOpcode';
const InvalidJumpDestError = 'InvalidJumpDestError';
const StackDepthLimitError = 'StackDepthLimitError';
const WriteInStaticContext = 'WriteInStaticContext';
const OutOfBoundsRead = 'OutOfBoundsRead';
const InvalidParameter = 'InvalidParameter';
const InvalidContractPrefix = 'InvalidContractPrefix';
const AddressCollision = 'AddressCollision';
const KZGProofError = 'KZGProofError';

func InvalidOpcodeError(param: felt) -> EthereumException {
    let param = param * 2 ** 30;
    let error_string = InvalidOpcode + param;
    let res = EthereumException(error_string);
    return res;
}
