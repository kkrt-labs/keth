from starkware.cairo.lang.compiler.encode import decode_instruction
from starkware.cairo.lang.compiler.identifier_definition import TypeDefinition
from starkware.cairo.lang.compiler.instruction import Instruction, Register
from starkware.cairo.lang.compiler.program import Program

from cairo_addons.testing.utils import flatten


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

    instructions = [decode_instruction(d, imm) for d, imm in zip(data, data[1:] + [0])]

    if any(i.op1_addr == Instruction.Op1Addr.IMM for i in instructions):
        raise ValueError(
            "ModBuiltin circuits don't support constants. To use a constant, add an input "
            "to the circuit, e.g. write\n\n"
            "```cairo\n"
            "func inv(x: felt, k: felt) -> felt {\n"
            "    return k / x;\n"
            "    end:\n"
            "}\n"
            "```\n\n"
            "instead of\n\n"
            "```cairo\n"
            "func inv(x: felt) -> felt {\n"
            "    return 1 / x;\n"
            "    end:\n"
            "}\n"
            "```"
        )

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
        for i in instructions
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
        for i, _ap in zip(instructions, ap)
    ]

    # Extract the offsets of the add and mul instructions
    add = flatten(
        [op for op, i in zip(ops, instructions) if i.res == Instruction.Res.ADD]
    )
    mul = flatten(
        [op for op, i in zip(ops, instructions) if i.res == Instruction.Res.MUL]
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
        "add_mod_offsets_ptr": [mapping[offset] * 4 for offset in add],
        "add_mod_n": len(add) // 3,
        "mul_mod_offsets_ptr": [mapping[offset] * 4 for offset in mul],
        "mul_mod_n": len(mul) // 3,
        "total_offset": len(indexes) * 4,
        "return_data_size": return_data_size * 4,
    }
