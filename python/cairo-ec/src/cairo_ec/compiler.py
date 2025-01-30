from starkware.cairo.lang.compiler.encode import decode_instruction
from starkware.cairo.lang.compiler.identifier_definition import TypeDefinition
from starkware.cairo.lang.compiler.instruction import Instruction, Register
from starkware.cairo.lang.compiler.program import Program

from cairo_addons.testing.utils import flatten


def circuit_compile(cairo_program: Program, circuit: str):
    start = cairo_program.get_label(circuit)
    stop = cairo_program.get_label(f"{circuit}.end")
    return_data_type = cairo_program.get_identifier(
        f"{circuit}.Return", TypeDefinition
    ).cairo_type
    return_data_size = len(getattr(return_data_type, "members", [""]))
    data = cairo_program.data[start:stop]

    instructions = [decode_instruction(d, imm) for d, imm in zip(data, data[1:] + [0])]
    ap_updates = [
        {
            Instruction.ApUpdate.ADD1: 1,
            Instruction.ApUpdate.ADD2: 2,
            Instruction.ApUpdate.REGULAR: 0,
        }.get(i.ap_update, i.imm or 0)
        for i in instructions
    ]
    ap = [sum(ap_updates[:i]) for i in range(len(ap_updates))]
    ops = [
        (
            i.off1 + (_ap if i.op0_register == Register.AP else 0),
            i.off2 + (_ap if i.op1_addr == Instruction.Op1Addr.AP else 0),
            i.off0 + ((_ap if i.dst_register == Register.AP else 0)),
        )
        for i, _ap in zip(instructions, ap)
    ]
    add = flatten(
        [op for op, i in zip(ops, instructions) if i.res == Instruction.Res.ADD]
    )
    mul = flatten(
        [op for op, i in zip(ops, instructions) if i.res == Instruction.Res.MUL]
    )

    # Reindex to start from 0 and to avoid memory holes
    # Happens when using values from fp.
    indexes = sorted(set(add + mul))
    mapping = dict(zip(indexes, range(len(indexes))))

    return {
        "add_mod_offsets_ptr": [mapping[offset] * 4 for offset in add],
        "add_mod_n": len(add) // 3,
        "mul_mod_offsets_ptr": [mapping[offset] * 4 for offset in mul],
        "mul_mod_n": len(mul) // 3,
        "total_offset": len(indexes) * 4,
        "return_data_size": return_data_size * 4,
    }
