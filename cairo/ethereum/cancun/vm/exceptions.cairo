struct ExceptionalHalt {
    value: felt,
}

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

func InvalidOpcodeError(param: felt) -> ExceptionalHalt {
    let param = param * 2 ** 30;
    let error_string = InvalidOpcode + param;
    let res = ExceptionalHalt(error_string);
    return res;
}
