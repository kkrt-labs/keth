import functools
import json
import re
from pathlib import Path
from types import MethodType
from typing import Optional

import toml
from eth_utils.address import to_checksum_address
from hexbytes import HexBytes
from web3 import Web3
from web3.exceptions import NoABIFunctionsFound

WEB3 = Web3()
CONTRACT_ADDRESS = to_checksum_address(f"0x{0xc0de:040x}")


@functools.lru_cache()
def get_solidity_artifacts(
    contract_app: str, contract_name: str, version: Optional[str] = None
):
    try:
        foundry_file_path = Path(__file__).parents[3] / "foundry.toml"
    except (NameError, FileNotFoundError):
        foundry_file_path = Path("foundry.toml")
    base_path = foundry_file_path.parent
    foundry_file = toml.loads(foundry_file_path.read_text())
    version_pattern = version if version else r"(\.[\d.]+)?"
    all_compilation_outputs = [
        json.load(open(file))
        for file in (base_path / Path(foundry_file["profile"]["default"]["out"])).glob(
            f"**/{contract_app}.sol/{contract_name}*.json"
        )
        if re.match(re.compile(f"{contract_name}{version_pattern}$"), file.stem)
    ]
    if len(all_compilation_outputs) != 1:
        raise ValueError(
            f"Cannot locate a unique compilation output for target {contract_name}:\n"
            f"found {len(all_compilation_outputs)} outputs:\n{all_compilation_outputs}"
        )
    return all_compilation_outputs[0]


@functools.lru_cache()
def get_contract(contract_app, contract_name, address=CONTRACT_ADDRESS):
    def _wrap_fun(fun):
        def _wrapper(self, *args, **kwargs):

            signer = kwargs.pop("signer")
            if signer is None:
                raise ValueError("Signer is required")
            value = kwargs.pop("value", 0)
            data = self.get_function_by_name(fun)(
                *args, **kwargs
            )._encode_transaction_data()
            return {"to": address, "value": value, "data": data, "signer": signer}

        return _wrapper

    artifacts = get_solidity_artifacts(contract_app, contract_name)
    contract = WEB3.eth.contract(
        address=address,
        abi=artifacts["abi"],
        bytecode=artifacts["bytecode"]["object"],
    )
    contract.bytecode_runtime = HexBytes(artifacts["deployedBytecode"]["object"])
    try:
        for fun in contract.functions:
            setattr(contract, fun.fn_name, MethodType(_wrap_fun(fun.fn_name), contract))
    except (NoABIFunctionsFound, TypeError):
        pass

    return contract
