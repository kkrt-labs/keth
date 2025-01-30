from typing import List

from starkware.cairo.lang.compiler.encode import decode_instruction
from starkware.cairo.lang.compiler.instruction import Instruction, Register

from cairo_addons.testing.utils import flatten


def compile_circuit(data: List[int]):

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
    add_u384 = [(mapping[offset]) * 4 for offset in add]
    mul_u384 = [(mapping[offset]) * 4 for offset in mul]

    return add_u384, mul_u384, len(indexes) * 4
