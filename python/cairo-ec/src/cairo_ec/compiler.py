from starkware.cairo.lang.compiler.encode import decode_instruction
from starkware.cairo.lang.compiler.identifier_definition import (
    StructDefinition,
    TypeDefinition,
)
from starkware.cairo.lang.compiler.instruction import Instruction, Register
from starkware.cairo.lang.compiler.program import Program

from cairo_addons.testing.utils import flatten
from cairo_addons.utils.uint384 import int_to_uint384


def circuit_compile(cairo_program: Program, circuit: str):
    """
    Compile a circuit from a Cairo program.

    Args:
        cairo_program: The Cairo program to compile.
        circuit: The name of the circuit (cairo label) to compile.

    Returns:
        A dictionary containing the compiled circuit data.

    The circuit should also define a end label right after the return opcode
    to slice the compiled CASM appropriately.

    The compiler works by retrieving from the compiled cairo program the instructions
    between the start and end labels. Given the Cairo instruction set, these are either + or *
    operations defined over the memory with addresses described as offsets relative to the
    application pointer (ap) or the frame pointer (fp). Given the fact that fp == ap at the
    beginning of a function, we don't need to distinguish between the two here.

    Because ModBuiltin circuits don't have the possibility to inject constants values, the cairo program
    should only contain operations between variables. As such, expressions like `a + 1` or `1 / a`
    are not supported and will raise an error.
    """
    start = cairo_program.get_label(circuit)
    stop = cairo_program.get_label(f"{circuit}.end")
    data = cairo_program.data[start:stop]

    instructions = []
    offset_bits = 16
    n_flags = 15
    for d, imm in zip(data, data[1:] + [0]):
        if d < 0 or d >= 2 ** (3 * offset_bits + n_flags):
            continue
        instructions.append(decode_instruction(d, imm))

    if not instructions[-1].pc_update == Instruction.PcUpdate.JUMP:
        raise ValueError("The circuit should end with a return instruction")
    instructions.pop()
    if any(i.pc_update == Instruction.PcUpdate.JUMP for i in instructions):
        raise ValueError("The circuit should not contain any jump instruction")

    # Extract immediate values (constants added by the compiler) to put them as inputs
    # First get the unique list of the required constants
    constants = {i.imm for i in instructions if i.op1_addr == Instruction.Op1Addr.IMM}
    # There may be something better to do but for now we just change res = Res.OP1 to res = 0 + op1
    if any(i.res == Instruction.Res.OP1 for i in instructions):
        constants.add(0)
    constants = list(constants)
    # Arguments of a function are always at fp - 3 - n where n is the index of the argument
    args = list(
        cairo_program.get_identifier(f"{circuit}.Args", StructDefinition).members.keys()
    )
    # We put the constants before the args, so the initial offset is 3 + len(args)
    constants_offset = 3 + len(args)

    instruction_compiled = []
    while instructions:
        i = instructions.pop(0)

        # Update res = Res.OP1 to res = 0 + op1
        if i.res == Instruction.Res.OP1:
            i.off1 = -constants_offset - constants.index(0)
            i.op0_register = Register.FP
            i.res = Instruction.Res.ADD

        # Use added input constant for immediate value
        if i.op1_addr == Instruction.Op1Addr.IMM:
            i.op1_addr = Instruction.Op1Addr.FP
            i.off2 = -constants_offset - constants.index(i.imm)
            i.ap_update = Instruction.ApUpdate.ADD1
            i.imm = None
            # pop the next instruction which is the imm value
            instructions.pop(0)

        instruction_compiled.append(i)

    # Reverse the constants because they are read backwards.
    # This list needs then to be prepended to the function arguments.
    constants.reverse()

    # Each instruction is of the form dst = op0 +/* op1 where op0, op1 and dst are
    # defined as offsets relative to the application pointer (ap).
    # Because the ap is updated at each instruction, we compute the ap offset
    # at each instruction with a cumulative sum of the ap_updates.
    ap_updates = [
        {
            Instruction.ApUpdate.ADD1: 1,
            Instruction.ApUpdate.ADD2: 2,
            Instruction.ApUpdate.REGULAR: 0,
        }.get(i.ap_update, i.imm or 0)
        for i in instruction_compiled
    ]
    ap = [sum(ap_updates[:i]) for i in range(len(ap_updates))]

    # Compute the total offset of each operand at each instruction
    # by adding the offset at the instruction to the offset at the operand (ap).
    # Note that if the base register is not ap, it's fp, meaning that the offset
    # is 0.
    ops = [
        (
            i.off1 + (_ap if i.op0_register == Register.AP else 0),
            i.off2 + (_ap if i.op1_addr == Instruction.Op1Addr.AP else 0),
            i.off0 + ((_ap if i.dst_register == Register.AP else 0)),
        )
        for i, _ap in zip(instruction_compiled, ap)
    ]

    # Extract the offsets of the add and mul instructions
    add = flatten(
        [op for op, i in zip(ops, instruction_compiled) if i.res == Instruction.Res.ADD]
    )
    mul = flatten(
        [op for op, i in zip(ops, instruction_compiled) if i.res == Instruction.Res.MUL]
    )

    if len(add) + len(mul) != 3 * len(ops):
        raise ValueError(
            "Extracting add and mul instructions led to an inconsistent number of instructions"
        )

    # Reindex to start from 0 and to avoid memory holes
    # Happens when using values from fp (available at [fp - 3 + i]).
    indexes = sorted(set(add + mul))
    mapping = dict(zip(indexes, range(len(indexes))))

    # Get the size of the return value. The return opcode writes in order in ap the values it's about to return.
    # This means that the last n values of the ModBuiltin circuit are the return values.
    return_data_size = len(
        getattr(
            cairo_program.get_identifier(
                f"{circuit}.Return", TypeDefinition
            ).cairo_type,
            "members",
            [""],
        )
    )
    return {
        "constants": [int_to_uint384(c) for c in constants],
        "args": args,
        "add_mod_offsets_ptr": [mapping[offset] * 4 for offset in add],
        "add_mod_n": len(add) // 3,
        "mul_mod_offsets_ptr": [mapping[offset] * 4 for offset in mul],
        "mul_mod_n": len(mul) // 3,
        "total_offset": len(indexes) * 4,
        "return_data_size": return_data_size * 4,
    }
