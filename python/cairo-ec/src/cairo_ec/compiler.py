from itertools import accumulate
from typing import Any, Dict, List, Tuple

from starkware.cairo.lang.compiler.ast.cairo_types import (
    TypeFelt,
    TypeStruct,
    TypeTuple,
)
from starkware.cairo.lang.compiler.encode import decode_instruction
from starkware.cairo.lang.compiler.identifier_definition import (
    MemberDefinition,
    StructDefinition,
    TypeDefinition,
)
from starkware.cairo.lang.compiler.instruction import Instruction, Register
from starkware.cairo.lang.compiler.program import Program

from cairo_addons.testing.serde import get_struct_definition
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
    """
    start = cairo_program.get_label(circuit)
    stop = cairo_program.get_label(f"{circuit}.end")
    data = cairo_program.data[start:stop]

    instructions = []
    idx = 0
    # Decode instructions
    while idx < len(data):
        if idx + 1 < len(data):
            inst = decode_instruction(data[idx], data[idx + 1])
            instructions.append(inst)
            if inst.op1_addr == Instruction.Op1Addr.IMM:
                idx += 2
            else:
                idx += 1
        # Last instruction
        else:
            inst = decode_instruction(data[idx], 0)
            instructions.append(inst)
            if inst.op1_addr == Instruction.Op1Addr.IMM:
                raise ValueError(
                    f"Last instruction on a single-word at {idx} cannot use an immediate value."
                )
            else:
                idx += 1

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
    args, args_size = extract_args(cairo_program, circuit)
    # We put the constants before the args, so the initial offset is 3 + size of the arguments
    constants_offset = 3 + args_size

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

    structs = extract_structs(cairo_program, circuit)
    return_values = extract_return_values(cairo_program, circuit)
    return_names = [value["name"] for value in return_values]
    return_offsets = [value["offset"] for value in return_values]
    cumul_offsets = list(accumulate(return_offsets))
    cumul_offsets.reverse()

    return {
        "constants": [int_to_uint384(c) for c in constants],
        "args": args,
        "structs": structs,
        "add_mod_offsets_ptr": [mapping[offset] * 4 for offset in add],
        "add_mod_n": len(add) // 3,
        "mul_mod_offsets_ptr": [mapping[offset] * 4 for offset in mul],
        "mul_mod_n": len(mul) // 3,
        "total_offset": len(indexes) * 4,
        "return_names": return_names,
        "return_offsets": cumul_offsets,
    }


def extract_return_values(cairo_program: Program, circuit: str) -> List[Dict[str, int]]:
    """
    Extract return value details from a Cairo program circuit's Return type.
    Returns:
        List of {name: str, offset: int} containing return value names and their offsets
    """

    def calculate_offset(member_type: Any, current_offset: int = 0) -> int:
        """Recursively calculate the offset for a member type."""
        if isinstance(member_type, TypeFelt):
            return current_offset + 4
        if not isinstance(member_type, TypeStruct):
            raise ValueError("Member type must be TypeFelt or TypeStruct")

        struct_def = get_struct_definition(
            cairo_program.identifiers, member_type.scope.path
        )

        for member in struct_def.members.values():
            current_offset = calculate_offset(member.cairo_type, current_offset)
        return current_offset

    # Get return type definition
    return_type = cairo_program.get_identifier(
        f"{circuit}.Return", TypeDefinition
    ).cairo_type

    # Collect return values based on type
    return_values = []

    if isinstance(return_type, TypeFelt):
        return_values.append({"name": "UInt384", "member": return_type})
    elif isinstance(return_type, TypeStruct):
        # Remove the CircuitInput suffix from the struct name if it exists
        name = return_type.scope.path[-1].removesuffix("CircuitInput")
        return_values.append({"name": name, "member": return_type})
    elif isinstance(return_type, TypeTuple):
        for item in return_type.types:
            if isinstance(item, TypeFelt):
                return_values.append({"name": "UInt384", "member": item})
            elif isinstance(item, TypeStruct):
                name = item.scope.path[-1].removesuffix("CircuitInput")
                return_values.append({"name": name, "member": item})

    # Calculate offsets for each return value
    return [
        {"name": value["name"], "offset": calculate_offset(value["member"])}
        for value in return_values
    ]


def extract_args(cairo_program: Program, circuit: str) -> List[Dict[str, Any]]:
    """
    Extract argument details from a Cairo program circuit's Args struct.
    Returns:
        List of {name: str, type: str, path: List[str], offset: int} containing argument details
    """

    def process_struct_member(
        member: MemberDefinition, base_path: str, args_list: List[str]
    ) -> Tuple[List[str], int]:
        """Recursively process struct members and build argument paths."""
        if isinstance(member.cairo_type, TypeFelt):
            args_list.append(base_path)
            return args_list

        if not isinstance(member.cairo_type, TypeStruct):
            raise ValueError("Member type must be TypeFelt or TypeStruct")

        struct_def = get_struct_definition(
            cairo_program.identifiers, member.cairo_type.scope.path
        )
        struct_name = struct_def.full_name.path[-1]

        if struct_name == "UInt384":
            args_list.append(base_path)
            return args_list

        for member_name, member_def in struct_def.members.items():
            new_path = f"{base_path}.{member_name}"
            args_list = process_struct_member(member_def, new_path, args_list)

        return args_list

    # Get Args struct members
    args = cairo_program.get_identifier(f"{circuit}.Args", StructDefinition)

    result = []

    for name, member in args.members.items():
        if isinstance(member.cairo_type, TypeFelt):
            result.append({"name": name, "type": "UInt384", "path": [name]})
        elif isinstance(member.cairo_type, TypeStruct):
            struct_def = get_struct_definition(
                cairo_program.identifiers, member.cairo_type.scope.path
            )
            struct_name = struct_def.full_name.path[-1].removesuffix("CircuitInput")

            path_list = []
            path_list = process_struct_member(member, name, path_list)

            result.append({"name": name, "type": struct_name, "path": path_list})

    return result, args.size


def extract_structs(cairo_program: Program, circuit: str) -> List[Dict[str, Any]]:
    """
    Extract and flatten struct definitions from a Cairo program circuit.
    Returns:
        List of {name: str, members: List[Dict[str, Any]]} containing struct names and their members
    """

    def process_struct_type(
        member_type, processed_structs: set
    ) -> Dict[str, Any] | None:
        """Process a single struct type and its nested members recursively."""
        if isinstance(member_type, TypeFelt):
            return None
        if not isinstance(member_type, TypeStruct):
            raise ValueError("Member type must be TypeFelt or TypeStruct")

        struct_def = get_struct_definition(
            cairo_program.identifiers, member_type.scope.path
        )
        struct_name = struct_def.full_name.path[-1].removesuffix("CircuitInput")
        processed_structs.add(struct_name)

        members = []
        for name, member in struct_def.members.items():
            member_info = {
                "name": name,
                "type": (
                    "felt"
                    if isinstance(member.cairo_type, TypeFelt)
                    else member.cairo_type.scope.path[-1]
                ),
                "nested": process_struct_type(member.cairo_type, processed_structs),
            }
            members.append(member_info)

        return {"name": struct_name, "members": members}

    # Collect all struct types from Args and Return
    processed_structs = set()
    struct_types = []

    # Handle return type
    return_type = cairo_program.get_identifier(
        f"{circuit}.Return", TypeDefinition
    ).cairo_type
    if isinstance(return_type, TypeStruct):
        struct_types.append(return_type)
    elif isinstance(return_type, TypeTuple):
        struct_types.extend(t for t in return_type.types if isinstance(t, TypeStruct))

    # Handle argument types
    args = cairo_program.get_identifier(f"{circuit}.Args", StructDefinition).members
    struct_types.extend(m.cairo_type for m in args.values())

    # Process all collected struct types
    result = []
    seen_names = set()

    for struct_type in struct_types:
        struct_data = process_struct_type(struct_type, processed_structs)
        if struct_data and struct_data["name"] not in seen_names:
            result.append(struct_data)
            seen_names.add(struct_data["name"])
            # Add any new nested structs
            for member in struct_data["members"]:
                if nested := member["nested"]:
                    if nested["name"] not in seen_names:
                        result.append(nested)
                        seen_names.add(nested["name"])

    return result
