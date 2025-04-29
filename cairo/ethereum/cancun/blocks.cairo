from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from starkware.cairo.common.alloc import alloc
from ethereum_types.numeric import U64, U256, Uint, bool
from ethereum_types.bytes import Bytes, Bytes8, Bytes32, TupleBytes, TupleBytes32
from ethereum.cancun.fork_types import Address, Bloom, Root
from ethereum.crypto.hash import Hash32
from ethereum.cancun.transactions_types import LegacyTransaction, LegacyTransaction__hash__
from cairo_core.bytes_impl import (
    Bytes__hash__,
    Bytes20__hash__,
    TupleBytes32__hash__,
    Bytes256__hash__,
)
from cairo_core.hash.blake2s import blake2s, blake2s_add_uint256, blake2s_add_felt

struct WithdrawalStruct {
    index: U64,
    validator_index: U64,
    address: Address,
    amount: U256,
}

struct Withdrawal {
    value: WithdrawalStruct*,
}

func Withdrawal__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(self: Withdrawal) -> Hash32 {
    alloc_locals;
    let (local data) = alloc();
    let data_start = data;
    with data {
        blake2s_add_felt(self.value.index.value, 0);
        blake2s_add_felt(self.value.validator_index.value, 0);
        blake2s_add_felt(self.value.address.value, 0);
        blake2s_add_uint256([self.value.amount.value]);
    }

    let n_bytes = 32 * WithdrawalStruct.SIZE;
    let (res) = blake2s(data=data_start, n_bytes=n_bytes);
    tempvar hash = Hash32(value=new res);
    return hash;
}

struct TupleWithdrawalStruct {
    data: Withdrawal*,
    len: felt,
}

struct TupleWithdrawal {
    value: TupleWithdrawalStruct*,
}

func TupleWithdrawal__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    self: TupleWithdrawal
) -> Hash32 {
    alloc_locals;
    let (acc) = alloc();
    let acc_start = acc;
    let index = 0;
    _innerTupleWithdrawal__hash__{acc=acc, index=index}(self);
    let n_bytes = 32 * self.value.len;
    let (res) = blake2s(data=acc_start, n_bytes=n_bytes);
    tempvar hash = Hash32(value=new res);
    return hash;
}

func _innerTupleWithdrawal__hash__{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, acc: felt*, index: felt
}(self: TupleWithdrawal) {
    if (index == self.value.len) {
        return ();
    }

    let item = self.value.data[index];
    let item_hash = Withdrawal__hash__(item);
    blake2s_add_uint256{data=acc}([item_hash.value]);
    let index = index + 1;
    return _innerTupleWithdrawal__hash__(self);
}

struct HeaderStruct {
    parent_hash: Hash32,
    ommers_hash: Hash32,
    coinbase: Address,
    state_root: Root,
    transactions_root: Root,
    receipt_root: Root,
    bloom: Bloom,
    difficulty: Uint,
    number: Uint,
    gas_limit: Uint,
    gas_used: Uint,
    timestamp: U256,
    extra_data: Bytes,
    prev_randao: Bytes32,
    nonce: Bytes8,
    base_fee_per_gas: Uint,
    withdrawals_root: Root,
    blob_gas_used: U64,
    excess_blob_gas: U64,
    parent_beacon_block_root: Root,
}

struct Header {
    value: HeaderStruct*,
}

func Header__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(self: Header) -> Hash32 {
    alloc_locals;

    let bloom_hash = Bytes256__hash__(self.value.bloom);
    let extra_data_hash = Bytes__hash__(self.value.extra_data);

    let (local data) = alloc();
    let data_start = data;
    with data {
        blake2s_add_uint256([self.value.parent_hash.value]);
        blake2s_add_uint256([self.value.ommers_hash.value]);
        blake2s_add_felt(self.value.coinbase.value, 0);
        blake2s_add_uint256([self.value.state_root.value]);
        blake2s_add_uint256([self.value.transactions_root.value]);
        blake2s_add_uint256([self.value.receipt_root.value]);
        blake2s_add_uint256([bloom_hash.value]);
        blake2s_add_felt(self.value.difficulty.value, 0);
        blake2s_add_felt(self.value.number.value, 0);
        blake2s_add_felt(self.value.gas_limit.value, 0);
        blake2s_add_felt(self.value.gas_used.value, 0);
        blake2s_add_uint256([self.value.timestamp.value]);
        blake2s_add_uint256([extra_data_hash.value]);
        blake2s_add_uint256([self.value.prev_randao.value]);
        blake2s_add_felt(self.value.nonce.value, 0);
        blake2s_add_felt(self.value.base_fee_per_gas.value, 0);
        blake2s_add_uint256([self.value.withdrawals_root.value]);
        blake2s_add_felt(self.value.blob_gas_used.value, 0);
        blake2s_add_felt(self.value.excess_blob_gas.value, 0);
        blake2s_add_uint256([self.value.parent_beacon_block_root.value]);
    }

    let n_bytes = 32 * HeaderStruct.SIZE;
    let (res) = blake2s(data=data_start, n_bytes=n_bytes);
    tempvar hash = Hash32(value=new res);
    return hash;
}

struct TupleHeaderStruct {
    data: Header*,
    len: felt,
}

struct TupleHeader {
    value: TupleHeaderStruct*,
}

struct LogStruct {
    address: Address,
    topics: TupleBytes32,
    data: Bytes,
}

struct Log {
    value: LogStruct*,
}

func Log__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(self: Log) -> Hash32 {
    alloc_locals;
    let address_hash = Bytes20__hash__(self.value.address);
    let topics_hash = TupleBytes32__hash__(self.value.topics);
    let data_hash = Bytes__hash__(self.value.data);
    let (local buffer) = alloc();
    let buffer_start = buffer;
    blake2s_add_uint256{data=buffer}([address_hash.value]);
    blake2s_add_uint256{data=buffer}([topics_hash.value]);
    blake2s_add_uint256{data=buffer}([data_hash.value]);
    let n_bytes = 32 * LogStruct.SIZE;
    let (res) = blake2s(data=buffer_start, n_bytes=n_bytes);
    tempvar hash = Hash32(value=new res);
    return hash;
}

struct TupleLogStruct {
    data: Log*,
    len: felt,
}

struct TupleLog {
    value: TupleLogStruct*,
}

func TupleLog__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(self: TupleLog) -> Hash32 {
    alloc_locals;
    let (acc) = alloc();
    let acc_start = acc;
    let index = 0;
    _innerTupleLog__hash__{acc=acc, index=index}(self);
    let n_bytes = 32 * self.value.len;
    let (res) = blake2s(data=acc_start, n_bytes=n_bytes);
    tempvar hash = Hash32(value=new res);
    return hash;
}

func _innerTupleLog__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*, acc: felt*, index: felt}(
    self: TupleLog
) {
    if (index == self.value.len) {
        return ();
    }

    let item = self.value.data[index];
    let item_hash = Log__hash__(item);
    blake2s_add_uint256{data=acc}([item_hash.value]);
    let index = index + 1;
    return _innerTupleLog__hash__(self);
}

struct ReceiptStruct {
    succeeded: bool,
    cumulative_gas_used: Uint,
    bloom: Bloom,
    logs: TupleLog,
}

struct Receipt {
    value: ReceiptStruct*,
}

struct UnionBytesLegacyTransactionEnum {
    bytes: Bytes,
    legacy_transaction: LegacyTransaction,
}

struct UnionBytesLegacyTransaction {
    value: UnionBytesLegacyTransactionEnum*,
}

func UnionBytesLegacyTransaction__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    self: UnionBytesLegacyTransaction
) -> Hash32 {
    if (cast(self.value.bytes.value, felt) != 0) {
        let res = Bytes__hash__(self.value.bytes);
        return res;
    }

    let legacy_tx = self.value.legacy_transaction;
    let legacy_tx_hash = LegacyTransaction__hash__(legacy_tx);
    return legacy_tx_hash;
}

struct OptionalUnionBytesLegacyTransaction {
    value: UnionBytesLegacyTransactionEnum*,
}

struct TupleUnionBytesLegacyTransactionStruct {
    data: UnionBytesLegacyTransaction*,
    len: felt,
}

struct TupleUnionBytesLegacyTransaction {
    value: TupleUnionBytesLegacyTransactionStruct*,
}

func TupleUnionBytesLegacyTransaction__hash__{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(
    self: TupleUnionBytesLegacyTransaction
) -> Hash32 {
    alloc_locals;
    let (acc) = alloc();
    let acc_start = acc;
    let index = 0;
    _innerTupleUnionBytesLegacyTransaction__hash__{acc=acc, index=index}(self);

    let n_bytes = 32 * self.value.len;
    let (res) = blake2s(data=acc_start, n_bytes=n_bytes);
    tempvar hash = Hash32(value=new res);
    return hash;
}

func _innerTupleUnionBytesLegacyTransaction__hash__{
    range_check_ptr, bitwise_ptr: BitwiseBuiltin*, acc: felt*, index: felt
}(self: TupleUnionBytesLegacyTransaction) {
    if (index == self.value.len) {
        return ();
    }

    let item = self.value.data[index];
    let item_hash = UnionBytesLegacyTransaction__hash__(item);
    blake2s_add_uint256{data=acc}([item_hash.value]);
    let index = index + 1;
    return _innerTupleUnionBytesLegacyTransaction__hash__(self);
}

struct UnionBytesReceiptEnum {
    bytes: Bytes,
    receipt: Receipt,
}

struct UnionBytesReceipt {
    value: UnionBytesReceiptEnum*,
}

struct OptionalUnionBytesReceipt {
    value: UnionBytesReceiptEnum*,
}

struct UnionBytesWithdrawalEnum {
    bytes: Bytes,
    withdrawal: Withdrawal,
}

struct UnionBytesWithdrawal {
    value: UnionBytesWithdrawalEnum*,
}

struct OptionalUnionBytesWithdrawal {
    value: UnionBytesWithdrawalEnum*,
}

struct BlockStruct {
    header: Header,
    transactions: TupleUnionBytesLegacyTransaction,
    ommers: TupleHeader,
    withdrawals: TupleWithdrawal,
}

struct Block {
    value: BlockStruct*,
}

struct ListBlockStruct {
    data: Block*,
    len: felt,
}

struct ListBlock {
    value: ListBlockStruct*,
}
