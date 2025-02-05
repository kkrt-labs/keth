from ethereum.cancun.vm import Environment as OriginalEnvironment
from ethereum.cancun.vm import Evm as OriginalEvm
from ethereum.cancun.vm import Message as OriginalMessage
from ethereum.cancun.vm.interpreter import (
    MessageCallOutput as OriginalMessageCallOutput,
)

from tests.utils.args_gen import Environment as MockEnvironment
from tests.utils.args_gen import Evm as MockEvm
from tests.utils.args_gen import Message as MockMessage
from tests.utils.args_gen import MessageCallOutput as MockMessageCallOutput


def test_patches_active():
    assert OriginalEvm == MockEvm
    assert OriginalMessage == MockMessage
    assert OriginalEnvironment == MockEnvironment
    assert OriginalMessageCallOutput == MockMessageCallOutput
