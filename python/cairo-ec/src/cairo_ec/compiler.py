from itertools import accumulate

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

    TODO: Remove that comment ?
    Because ModBuiltin circuits don't have the possibility to inject constants values, the cairo program
    should only contain operations between variables. As such, expressions like `a + 1` or `1 / a`
    are not supported and will raise an error.
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
    # If it's a felt, the parameter key has a field cairo_type TypeFelt
    # If it's a struct, the parameter key has a field cairo_type TypeStruct
    # TypeStruct have a `scope` variable with the path as a list --> the key of the identifier dict !
    # How to extract the struct ?
    # A path is given to find the struct within the codebase (e.g. cairo_ec.curve.g1g2pair and last one is the struct name)
    # the cairo_program maintains a dict of all the identifiers, once you have the name of the structs, if not felt, lookup in the identifiers dict !!
    # How to create a struct in the file, with same structure but UInt384*
    # What about nested structs ? --> If a struct has struct members, need to unfold it until we find felt
    def extract_structs(cairo_program: Program, circuit: str):
        def extract_struct(
            cairo_program: Program, member_type, struct_set: set, is_nested: bool
        ):
            if isinstance(member_type, TypeFelt):
                return None
            elif isinstance(member_type, TypeStruct):
                member_struct = cairo_program.get_identifier(
                    member_type.scope, StructDefinition, True
                )
                struct_name = member_struct.full_name.path[-1]
                if struct_name in struct_set and not is_nested:
                    return None
                struct_set.add(struct_name)
                struct_members = []
                for (
                    struct_member_key,
                    struct_member_value,
                ) in member_struct.members.items():
                    struct_member_type = (
                        "felt"
                        if isinstance(struct_member_value.cairo_type, TypeFelt)
                        else "struct"
                    )
                    nested_struct_member = extract_struct(
                        cairo_program, struct_member_value.cairo_type, struct_set, True
                    )
                    struct_members.append(
                        {
                            "name": struct_member_key,
                            "type": struct_member_type,
                            "nested": nested_struct_member,
                        }
                    )
                return {"name": struct_name, "members": struct_members}
            else:
                raise ValueError(
                    "Member can only be an instance of TypeFelt or TypeStruct."
                )

        struct_set = set()
        return_members = cairo_program.get_identifier(
            f"{circuit}.Return", TypeDefinition
        )
        # Case 2: Return type is a single type
        # Case 3: Return type is a tuple
        all_structs = []
        if isinstance(return_members.cairo_type, TypeStruct):
            all_structs.append(return_members.cairo_type)
        elif isinstance(return_members.cairo_type, TypeTuple):
            for tuple_item in return_members.cairo_type.types:
                if isinstance(tuple_item, TypeStruct):
                    all_structs.append(tuple_item)

        for member in cairo_program.get_identifier(
            f"{circuit}.Args", StructDefinition
        ).members.values():
            all_structs.append(member.cairo_type)

        structs = [
            extract_struct(cairo_program, member_type, struct_set, False)
            for member_type in all_structs
        ]

        filtered_structs = [struct for struct in structs if struct is not None]

        flattened_structs = []
        struct_names = set()
        for struct in filtered_structs:
            flattened_structs.append(struct)
            struct_names.add(struct["name"])
            for member in struct["members"]:
                nested = member["nested"]
                if nested is not None and nested["name"] not in struct_names:
                    struct_names.add(nested["name"])
                    filtered_structs.append(member["nested"])

        return flattened_structs

    def extract_args(cairo_program: Program, circuit: str):
        def extract_full_arg_path(
            cairo_program,
            member: MemberDefinition,
            name: str,
            arg_path: str,
            args: list,
            offset: int,
        ):
            if isinstance(member.cairo_type, TypeFelt):
                args.append(arg_path)
                return (
                    arg_path,
                    offset + 1,
                )
            elif isinstance(member.cairo_type, TypeStruct):
                member_struct = cairo_program.get_identifier(
                    member.cairo_type.scope, StructDefinition, True
                )
                struct_name = member_struct.full_name.path[-1]
                if struct_name == "UInt384":
                    args.append(arg_path)
                    return arg_path, offset + 1
                for (
                    struct_member_key,
                    struct_member_value,
                ) in member_struct.members.items():
                    old_path = arg_path
                    new_path = arg_path + "." + struct_member_key
                    arg_path, offset = extract_full_arg_path(
                        cairo_program, struct_member_value, name, new_path, args, offset
                    )
                    arg_path = old_path
                return args, offset
            else:
                raise ValueError(
                    "Member can only be an instance of TypeFelt or TypeStruct."
                )

        args = list()
        args_members = cairo_program.get_identifier(
            f"{circuit}.Args", StructDefinition
        ).members
        for name, member in args_members.items():
            if isinstance(member.cairo_type, TypeFelt):
                args.append(
                    {"name": name, "type": "UInt384", "path": [name], "offset": 1}
                )
            elif isinstance(member.cairo_type, TypeStruct):
                member_struct = cairo_program.get_identifier(
                    member.cairo_type.scope, StructDefinition, True
                )
                path, offset = extract_full_arg_path(
                    cairo_program, member, name, name, [], 0
                )
                args.append(
                    {
                        "name": name,
                        "type": member_struct.full_name.path[-1],
                        "path": path,
                        "offset": offset,
                    }
                )
                path = []
        return args

    def extract_return_values(cairo_program: Program, circuit: str):
        # def extract_return_value_offset(
        #     cairo_program,
        #     member: MemberDefinition,
        #     name: str,
        #     offset: int,
        # ):
        #     if isinstance(member.cairo_type, TypeFelt):
        #         return offset + 1
        #     elif isinstance(member.cairo_type, TypeStruct):
        #         member_struct = cairo_program.get_identifier(
        #             member.cairo_type.scope, StructDefinition, True
        #         )
        #         struct_name = member_struct.full_name.path[-1]
        #         if struct_name == "UInt384":
        #             return offset + 1
        #         for struct_member_value in member_struct.members.values():
        #             offset = extract_return_value_offset(
        #                 cairo_program, struct_member_value, name, offset
        #             )
        #         return offset
        #     else:
        #         raise ValueError(
        #             "Member can only be an instance of TypeFelt or TypeStruct."
        #         )

        def extract_return_value_offset(
            cairo_program: Program, member_type, offset: int
        ):
            if isinstance(member_type, TypeFelt):
                return offset + 4
            elif isinstance(member_type, TypeStruct):
                member_struct = cairo_program.get_identifier(
                    member_type.scope, StructDefinition, True
                )
                for struct_member_value in member_struct.members.values():
                    offset = extract_return_value_offset(
                        cairo_program, struct_member_value.cairo_type, offset
                    )
                return offset
            else:
                raise ValueError(
                    "Member can only be an instance of TypeFelt or TypeStruct."
                )

        return_values = []
        return_members = cairo_program.get_identifier(
            f"{circuit}.Return", TypeDefinition
        )
        # Case 2: Return type is a single type
        # Case 3: Return type is a tuple
        if isinstance(return_members.cairo_type, TypeFelt):
            return_values.append(
                {"name": "UInt384", "member": return_members.cairo_type}
            )
        elif isinstance(return_members.cairo_type, TypeStruct):
            return_values.append(
                {
                    "name": return_members.cairo_type.scope.path[-1],
                    "member": return_members.cairo_type,
                }
            )
        elif isinstance(return_members.cairo_type, TypeTuple):
            for tuple_item in return_members.cairo_type.types:
                if isinstance(tuple_item, TypeFelt):
                    return_values.append({"name": "UInt384", "member": tuple_item})
                elif isinstance(tuple_item, TypeStruct):
                    return_values.append(
                        {"name": tuple_item.scope.path[-1], "member": tuple_item}
                    )

        return [
            {
                "name": return_value["name"],
                "offset": extract_return_value_offset(
                    cairo_program, return_value["member"], 0
                ),
            }
            for return_value in return_values
        ]

    structs = extract_structs(cairo_program, circuit)
    args = extract_args(cairo_program, circuit)
    return_values = extract_return_values(cairo_program, circuit)
    return_names = [value["name"] for value in return_values]
    return_offsets = [value["offset"] for value in return_values]
    cumul_offsets = list(accumulate(return_offsets))
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
