from pathlib import Path
from typing import Optional

from eth_utils.address import to_checksum_address
from starkware.cairo.lang.compiler.ast.cairo_types import (
    TypeFelt,
    TypePointer,
    TypeStruct,
    TypeTuple,
)
from starkware.cairo.lang.compiler.identifier_definition import (
    StructDefinition,
    TypeDefinition,
)
from starkware.cairo.lang.compiler.identifier_manager import MissingIdentifierError

from ethereum.base_types import (
    U64,
    U256,
    Bytes0,
    Bytes8,
    Bytes20,
    Bytes32,
    Bytes256,
    Uint,
)
from ethereum.cancun.blocks import Header, Log, Receipt, Withdrawal
from ethereum.cancun.fork_types import Account
from ethereum.cancun.transactions import (
    AccessListTransaction,
    BlobTransaction,
    FeeMarketTransaction,
    LegacyTransaction,
)
from ethereum.cancun.vm.gas import MessageCallGas


def get_cairo_type(program, name):
    identifiers = [
        value
        for key, value in program.identifiers.as_dict().items()
        if name in str(key) and name.split(".")[-1] == str(key).split(".")[-1]
    ]
    if len(identifiers) != 1:
        raise ValueError(f"Expected one type named {name}, found {identifiers}")
    identifier = identifiers[0]

    if isinstance(identifier, TypeDefinition):
        return identifier.cairo_type
    if isinstance(identifier, StructDefinition):
        return TypeStruct(scope=identifier.full_name, location=identifier.location)

    return identifier


def get_struct_definition(program, name):
    identifiers = [
        (
            value
            if isinstance(value, StructDefinition)
            else get_struct_definition(program, str(value.cairo_type.scope))
        )
        for key, value in program.identifiers.as_dict().items()
        if name in str(key)
        and name.split(".")[-1] == str(key).split(".")[-1]
        and (
            isinstance(value, StructDefinition)
            or (
                isinstance(value, TypeDefinition)
                and isinstance(value.cairo_type, TypeStruct)
            )
        )
    ]
    if len(identifiers) != 1:
        raise ValueError(f"Expected one struct named {name}, found {identifiers}")
    return identifiers[0]


class Serde:
    def __init__(self, segments, program, cairo_file=None):
        self.segments = segments
        self.memory = segments.memory
        self.program = program
        self.cairo_file = cairo_file or Path()

    @property
    def main_part(self):
        """
        Resolve the __main__ part of the cairo scope path.
        """
        parts = self.cairo_file.relative_to(Path.cwd()).with_suffix("").parts
        return parts[1:] if parts[0] == "cairo" else parts

    def serialize_list(self, segment_ptr, item_scope=None, list_len=None):
        item_identifier = (
            get_struct_definition(self.program, item_scope)
            if item_scope is not None
            else None
        )
        item_type = (
            TypeStruct(item_identifier.full_name)
            if item_scope is not None
            else TypeFelt()
        )
        item_size = item_identifier.size if item_identifier is not None else 1
        try:
            list_len = (
                list_len * item_size
                if list_len is not None
                else self.segments.get_segment_size(segment_ptr.segment_index)
            )
        except AssertionError as e:
            if (
                "compute_effective_sizes must be called before get_segment_used_size."
                in str(e)
            ):
                list_len = 1
            else:
                raise e
        output = []
        for i in range(0, list_len, item_size):
            try:
                output.append(self._serialize(item_type, segment_ptr + i))
            # Because there is no way to know for sure the length of the list, we stop when we
            # encounter an error.
            # trunk-ignore(ruff/E722)
            except:
                break
        return output

    def serialize_dict(self, dict_ptr, value_scope=None, dict_size=None):
        """
        Serialize a dict.
        """
        if dict_size is None:
            dict_size = self.segments.get_segment_size(dict_ptr.segment_index)
        output = {}
        value_scope = (
            get_struct_definition(self.program, value_scope).full_name
            if value_scope is not None
            else None
        )
        for dict_index in range(0, dict_size, 3):
            key = self.memory.get(dict_ptr + dict_index)
            value_ptr = self.memory.get(dict_ptr + dict_index + 2)
            if value_scope is None:
                output[key] = value_ptr
            else:
                output[key] = (
                    self.serialize_scope(value_scope, value_ptr)
                    if value_ptr != 0
                    else None
                )
        return output

    def serialize_pointers(self, name, ptr):
        """
        Serialize a pointer to a struct, e.g. Uint256*.
        """
        members = get_struct_definition(self.program, name).members
        output = {}
        for name, member in members.items():
            member_ptr = self.memory.get(ptr + member.offset)
            if member_ptr == 0 and isinstance(member.cairo_type, TypePointer):
                member_ptr = None
            output[name] = member_ptr
        return output

    def serialize_struct(self, name, ptr) -> Optional[dict]:
        """
        Serialize a struct, e.g. Uint256.
        """
        if ptr is None:
            return None
        members = get_struct_definition(self.program, name).members
        return {
            name: self._serialize(member.cairo_type, ptr + member.offset)
            for name, member in members.items()
        }

    def serialize_kakarot_account(self, ptr):
        raw = self.serialize_pointers("model.Account", ptr)
        return {
            "code": bytes(self.serialize_list(raw["code"], list_len=raw["code_len"])),
            "code_hash": self.serialize_uint256(raw["code_hash"]),
            "storage": self.serialize_dict(raw["storage_start"], "Uint256"),
            "transient_storage": self.serialize_dict(
                raw["transient_storage_start"], "Uint256"
            ),
            "valid_jumpdests": self.serialize_dict(raw["valid_jumpdests_start"]),
            "nonce": raw["nonce"],
            "balance": self.serialize_uint256(raw["balance"]),
            "selfdestruct": raw["selfdestruct"],
            "created": raw["created"],
        }

    def serialize_state(self, ptr):
        raw = self.serialize_pointers("model.State", ptr)
        return {
            "accounts": {
                to_checksum_address(f"{key:040x}"): value
                for key, value in self.serialize_dict(
                    raw["accounts_start"], "model.Account"
                ).items()
            },
            "events": self.serialize_list(
                raw["events"], "model.Event", list_len=raw["events_len"]
            ),
            "transfers": self.serialize_list(
                raw["transfers"], "model.Transfer", list_len=raw["transfers_len"]
            ),
        }

    def serialize_eth_transaction(self, ptr):
        raw = self.serialize_struct("model.Transaction", ptr)
        return {
            "signer_nonce": raw["signer_nonce"],
            "gas_limit": raw["gas_limit"],
            "max_priority_fee_per_gas": raw["max_priority_fee_per_gas"],
            "max_fee_per_gas": raw["max_fee_per_gas"],
            "destination": (
                to_checksum_address(f'0x{raw["destination"]:040x}')
                if raw["destination"]
                else None
            ),
            "amount": raw["amount"],
            "payload": ("0x" + bytes(raw["payload"][: raw["payload_len"]]).hex()),
            "access_list": (
                raw["access_list"][: raw["access_list_len"]]
                if raw["access_list"] is not None
                else []
            ),
            "chain_id": raw["chain_id"],
        }

    def serialize_message(self, ptr):
        raw = self.serialize_pointers("model.Message", ptr)
        return {
            "bytecode": self.serialize_list(
                raw["bytecode"], list_len=raw["bytecode_len"]
            ),
            "valid_jumpdest": list(
                self.serialize_dict(raw["valid_jumpdests_start"]).keys()
            ),
            "calldata": self.serialize_list(
                raw["calldata"], list_len=raw["calldata_len"]
            ),
            "caller": to_checksum_address(f'{raw["caller"]:040x}'),
            "value": self.serialize_uint256(raw["value"]),
            "parent": self.serialize_struct("model.Parent", raw["parent"]),
            "address": to_checksum_address(f'{raw["address"]:040x}'),
            "code_address": to_checksum_address(f'{raw["code_address"]:040x}'),
            "read_only": bool(raw["read_only"]),
            "is_create": bool(raw["is_create"]),
            "depth": raw["depth"],
            "env": self.serialize_struct("model.Environment", raw["env"]),
        }

    def serialize_evm(self, ptr):
        evm = self.serialize_struct("model.EVM", ptr)
        return {
            "message": evm["message"],
            "return_data": evm["return_data"][: evm["return_data_len"]],
            "program_counter": evm["program_counter"],
            "stopped": bool(evm["stopped"]),
            "gas_left": evm["gas_left"],
            "gas_refund": evm["gas_refund"],
            "reverted": evm["reverted"],
        }

    def serialize_stack(self, ptr):
        raw = self.serialize_pointers("model.Stack", ptr)
        stack_dict = self.serialize_dict(
            raw["dict_ptr_start"], "Uint256", raw["dict_ptr"] - raw["dict_ptr_start"]
        )
        return [stack_dict[i] for i in range(raw["size"])]

    def serialize_memory(self, ptr):
        raw = self.serialize_pointers("model.Memory", ptr)
        memory_dict = self.serialize_dict(
            raw["word_dict_start"], dict_size=raw["word_dict"] - raw["word_dict_start"]
        )
        return "".join(
            [f"{memory_dict.get(i, 0):032x}" for i in range(raw["words_len"] * 2)]
        )

    def serialize_rlp_item(self, ptr):
        raw = self.serialize_list(ptr)
        items = []
        for i in range(0, len(raw), 3):
            data_len = raw[i]
            data_ptr = raw[i + 1]
            is_list = raw[i + 2]
            if not is_list:
                items += [bytes(self.serialize_list(data_ptr)[:data_len])]
            else:
                items += [self.serialize_rlp_item(data_ptr)]
        return items

    def serialize_block_kakarot(self, ptr):
        raw = self.serialize_pointers("model.Block", ptr)
        header = self.serialize_struct("model.BlockHeader", raw["block_header"])
        if header is None:
            raise ValueError("Block header is None")
        header = {
            **header,
            "withdrawals_root": (
                self.serialize_uint256(header["withdrawals_root"])
                if header["withdrawals_root"] is not None
                else None
            ),
            "parent_beacon_block_root": (
                self.serialize_uint256(header["parent_beacon_block_root"])
                if header["parent_beacon_block_root"] is not None
                else None
            ),
            "requests_root": (
                self.serialize_uint256(header["requests_root"])
                if header["requests_root"] is not None
                else None
            ),
            "extra_data": bytes(header["extra_data"][: header["extra_data_len"]]),
            "bloom": bytes.fromhex("".join(f"{b:032x}" for b in header["bloom"])),
        }
        del header["extra_data_len"]
        return {
            "block_header": header,
            "transactions": self.serialize_list(
                raw["transactions"],
                "model.TransactionEncoded",
                list_len=raw["transactions_len"],
            ),
        }

    def serialize_option(self, ptr):
        raw = self.serialize_pointers("model.Option", ptr)
        if raw["is_some"] == 0:
            return None
        return raw["value"]

    def serialize_uint256(self, ptr):
        raw = self.serialize_struct("Uint256", ptr)
        return U256(raw["low"] + raw["high"] * 2**128)

    def serialize_message_call_gas(self, ptr):
        raw = self.serialize_struct("MessageCallGas", ptr)
        return MessageCallGas(cost=raw["cost"], stipend=raw["stipend"])

    def serialize_bool(self, ptr):
        raw = self.serialize_struct("bool", ptr)
        return bool(raw["value"])

    def serialize_u64(self, ptr):
        raw = self.serialize_struct("U64", ptr)
        return U64(raw["value"])

    def serialize_u128(self, ptr):
        raw = self.serialize_struct("U128", ptr)
        return Uint(raw["value"])

    def serialize_uint(self, ptr):
        raw = self.serialize_struct("Uint", ptr)
        return Uint(raw["value"])

    def serialize_u256(self, ptr):
        raw = self.serialize_struct("U256", ptr)
        return U256(raw["value"])

    def serialize_bytes0(self, ptr):
        raw = self.serialize_struct("Bytes0", ptr)
        assert raw["value"] == 0
        return Bytes0(b"")

    def serialize_bytes8(self, ptr):
        raw = self.serialize_struct("Bytes8", ptr)
        return Bytes8(raw["value"].to_bytes(8, "big"))

    def serialize_bytes20(self, ptr):
        raw = self.serialize_struct("Bytes20", ptr)
        return Bytes20(raw["value"].to_bytes(20, "big"))

    def serialize_bytes32(self, ptr):
        raw = self.serialize_struct("Bytes32", ptr)
        return Bytes32(raw["value"].to_bytes(32, "big"))

    def serialize_bytes256(self, ptr):
        return Bytes256(
            b"".join(
                b.to_bytes(16, "big")
                for b in self.serialize_list(self.memory.get(ptr), list_len=8 * 2)
            )
        )

    def serialize_bytes(self, ptr):
        raw = self.serialize_pointers("BytesStruct", self.memory.get(ptr))
        return bytes(self.serialize_list(raw["data"], list_len=raw["len"]))

    def serialize_tuple(self, ptr, item_scope):
        tuple_struct_ptr = self.serialize_pointers(f"Tuple{item_scope}", ptr)["value"]
        raw = self.serialize_pointers(f"Tuple{item_scope}Struct", tuple_struct_ptr)
        return tuple(self.serialize_list(raw["value"], item_scope, list_len=raw["len"]))

    def serialize_sequence(self, ptr, item_scope):
        sequence_struct_ptr = self.serialize_pointers(f"Sequence{item_scope}", ptr)[
            "value"
        ]
        raw = self.serialize_pointers(
            f"Sequence{item_scope}Struct", sequence_struct_ptr
        )
        return list(self.serialize_list(raw["value"], item_scope, list_len=raw["len"]))

    def serialize_enum(self, ptr, item_scope):
        enum_struct_ptr = self.serialize_pointers(f"{item_scope}", ptr)["value"]
        raw = self.serialize_pointers(f"{item_scope}Struct", enum_struct_ptr)
        raw = {key for key, value in raw.items() if value != 0 and value is not None}
        if len(raw) != 1:
            raise ValueError(
                f"Expected 1 item only to be relocatable in enum, got {len(raw)}"
            )
        key = list(raw)[0]
        members = get_struct_definition(self.program, f"{item_scope}Struct").members
        return self._serialize(
            members[key].cairo_type, enum_struct_ptr + members[key].offset
        )

    def serialize_account(self, ptr):
        raw = self.serialize_struct("Account", ptr)
        if raw is None:
            return None
        return Account(**raw["value"])

    def serialize_withdrawal(self, ptr):
        raw = self.serialize_struct("Withdrawal", ptr)
        if raw is None:
            return None
        return Withdrawal(**raw["value"])

    def serialize_header(self, ptr):
        raw = self.serialize_struct("Header", ptr)
        if raw is None:
            return None
        return Header(**raw["value"])

    def serialize_log(self, ptr):
        raw = self.serialize_struct("Log", ptr)
        if raw is None:
            return None
        return Log(**raw["value"])

    def serialize_receipt(self, ptr):
        raw = self.serialize_struct("Receipt", ptr)
        if raw is None:
            return None
        return Receipt(**raw["value"])

    def serialize_legacy_transaction(self, ptr):
        raw = self.serialize_struct("LegacyTransaction", ptr)
        if raw is None:
            return None
        return LegacyTransaction(**raw["value"])

    def serialize_access_list_transaction(self, ptr):
        raw = self.serialize_struct("AccessListTransaction", ptr)
        if raw is None:
            return None
        return AccessListTransaction(**raw["value"])

    def serialize_fee_market_transaction(self, ptr):
        raw = self.serialize_struct("FeeMarketTransaction", ptr)
        if raw is None:
            return None
        return FeeMarketTransaction(**raw["value"])

    def serialize_blob_transaction(self, ptr):
        raw = self.serialize_struct("BlobTransaction", ptr)
        if raw is None:
            return None
        return BlobTransaction(**raw["value"])

    def serialize_scope(self, scope, scope_ptr):
        # Corelib types
        scope_path = scope.path
        if "__main__" in scope_path:
            scope_path = self.main_part + scope_path[scope_path.index("__main__") + 1 :]

        if scope_path[-1] == "Uint256":
            return self.serialize_uint256(scope_ptr)

        # Gas types
        if scope_path == ("ethereum", "cancun", "vm", "gas", "MessageCallGas"):
            return self.serialize_message_call_gas(scope_ptr)

        # Base types
        if scope_path == ("ethereum", "base_types", "bool"):
            return self.serialize_bool(scope_ptr)
        if scope_path == ("ethereum", "base_types", "U64"):
            return self.serialize_u64(scope_ptr)
        if scope_path == ("ethereum", "base_types", "U128"):
            return self.serialize_u128(scope_ptr)
        if scope_path == ("ethereum", "base_types", "Uint"):
            return self.serialize_uint(scope_ptr)
        if scope_path == ("ethereum", "base_types", "U256"):
            return self.serialize_u256(scope_ptr)
        if scope_path == ("ethereum", "base_types", "Bytes0"):
            return self.serialize_bytes0(scope_ptr)
        if scope_path == ("ethereum", "base_types", "Bytes8"):
            return self.serialize_bytes8(scope_ptr)
        if scope_path == ("ethereum", "base_types", "Bytes20"):
            return self.serialize_bytes20(scope_ptr)
        if scope_path == ("ethereum", "base_types", "Bytes32"):
            return self.serialize_bytes32(scope_ptr)
        if scope_path == ("ethereum", "base_types", "Bytes256"):
            return self.serialize_bytes256(scope_ptr)
        if scope_path == ("ethereum", "base_types", "Bytes"):
            return self.serialize_bytes(scope_ptr)
        if scope_path == ("ethereum", "base_types", "TupleBytes"):
            return self.serialize_tuple(scope_ptr, "Bytes")
        if scope_path == ("ethereum", "base_types", "TupleBytes32"):
            return self.serialize_tuple(scope_ptr, "Bytes32")

        # RLP types
        if scope_path == ("ethereum", "rlp", "SequenceSimple"):
            return self.serialize_sequence(scope_ptr, "Simple")
        if scope_path == ("ethereum", "rlp", "Simple"):
            return self.serialize_enum(scope_ptr, "Simple")

        # Fork types
        if scope_path == ("ethereum", "cancun", "fork_types", "Account"):
            return self.serialize_account(scope_ptr)
        if scope_path == ("ethereum", "cancun", "fork_types", "TupleVersionedHash"):
            return self.serialize_tuple(scope_ptr, "VersionedHash")

        # Block types
        if scope_path == ("ethereum", "cancun", "blocks", "Withdrawal"):
            return self.serialize_withdrawal(scope_ptr)
        if scope_path == ("ethereum", "cancun", "blocks", "TupleWithdrawal"):
            return self.serialize_tuple(scope_ptr, "Withdrawal")
        if scope_path == ("ethereum", "cancun", "blocks", "Header"):
            return self.serialize_header(scope_ptr)
        if scope_path == ("ethereum", "cancun", "blocks", "TupleHeader"):
            return self.serialize_tuple(scope_ptr, "Header")
        if scope_path == ("ethereum", "cancun", "blocks", "Log"):
            return self.serialize_log(scope_ptr)
        if scope_path == ("ethereum", "cancun", "blocks", "TupleLog"):
            return self.serialize_tuple(scope_ptr, "Log")
        if scope_path == ("ethereum", "cancun", "blocks", "Receipt"):
            return self.serialize_receipt(scope_ptr)

        # Transaction types
        if scope_path == ("ethereum", "cancun", "transactions", "To"):
            return self.serialize_enum(scope_ptr, "To")
        if scope_path == ("ethereum", "cancun", "transactions", "TupleAccessList"):
            return self.serialize_tuple(scope_ptr, "AccessList")
        if scope_path == ("ethereum", "cancun", "transactions", "Transaction"):
            return self.serialize_enum(scope_ptr, "Transaction")
        if scope_path == ("ethereum", "cancun", "transactions", "LegacyTransaction"):
            return self.serialize_legacy_transaction(scope_ptr)
        if scope_path == (
            "ethereum",
            "cancun",
            "transactions",
            "AccessListTransaction",
        ):
            return self.serialize_access_list_transaction(scope_ptr)
        if scope_path == ("ethereum", "cancun", "transactions", "FeeMarketTransaction"):
            return self.serialize_fee_market_transaction(scope_ptr)
        if scope_path == ("ethereum", "cancun", "transactions", "BlobTransaction"):
            return self.serialize_blob_transaction(scope_ptr)

        # TODO: Remove these once EELS like migration is implemented
        if scope_path[-1] == "State":
            return self.serialize_state(scope_ptr)
        if scope_path[-1] == "Account":
            return self.serialize_kakarot_account(scope_ptr)
        if scope_path[-1] == "Transaction":
            return self.serialize_eth_transaction(scope_ptr)
        if scope_path[-1] == "Stack":
            return self.serialize_stack(scope_ptr)
        if scope_path[-1] == "Memory":
            return self.serialize_memory(scope_ptr)
        if scope_path[-1] == "Uint256":
            return self.serialize_uint256(scope_ptr)
        if scope_path[-1] == "Message":
            return self.serialize_message(scope_ptr)
        if scope_path[-1] == "EVM":
            return self.serialize_evm(scope_ptr)
        if scope_path[-2:] == ("RLP", "Item"):
            return self.serialize_rlp_item(scope_ptr)
        if scope_path[-1] == ("Block"):
            return self.serialize_block_kakarot(scope_ptr)
        if scope_path[-1] == ("Option"):
            return self.serialize_option(scope_ptr)
        try:
            return self.serialize_struct(str(scope), scope_ptr)
        except MissingIdentifierError:
            return scope_ptr

    def _serialize(self, cairo_type, ptr, length=1):
        if isinstance(cairo_type, TypePointer):
            # A pointer can be a pointer to one single struct or to the beginning of a list of structs.
            # As such, every pointer is considered a list of structs, with length 1 or more.
            pointee = self.memory.get(ptr)
            # Edge case: 0 pointers are not pointer but no data
            if pointee == 0:
                return None
            if isinstance(cairo_type.pointee, TypeFelt):
                return self.serialize_list(pointee)
            serialized = self.serialize_list(
                pointee, str(cairo_type.pointee.scope), list_len=length
            )
            if len(serialized) == 1:
                return serialized[0]
            return serialized
        if isinstance(cairo_type, TypeTuple):
            return [
                self._serialize(m.typ, ptr + i)
                for i, m in enumerate(cairo_type.members)
            ]
        if isinstance(cairo_type, TypeFelt):
            return self.memory.get(ptr)
        if isinstance(cairo_type, TypeStruct):
            return self.serialize_scope(cairo_type.scope, ptr)
        raise ValueError(f"Unknown type {cairo_type}")

    def get_offset(self, cairo_type):
        if hasattr(cairo_type, "members"):
            return len(cairo_type.members)
        else:
            try:
                identifier = get_struct_definition(self.program, str(cairo_type.scope))
                return len(identifier.members)
            except (ValueError, AttributeError):
                return 1

    def serialize(self, cairo_type, base_ptr, shift=None, length=None):
        shift = shift if shift is not None else self.get_offset(cairo_type)
        length = length if length is not None else shift
        return self._serialize(cairo_type, base_ptr - shift, length)
