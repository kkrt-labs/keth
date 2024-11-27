import os

os.environ["PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"] = "python"

import logging
import os

import starkware.cairo.lang.instances as LAYOUTS
from dotenv import load_dotenv
from hypothesis import Phase, Verbosity, settings

load_dotenv()
logger = logging.getLogger()


def pytest_addoption(parser):
    parser.addoption(
        "--profile-cairo",
        action="store_true",
        default=False,
        help="compute and dump TracerData for the VM runner: True or False",
    )
    parser.addoption(
        "--proof-mode",
        action="store_true",
        default=False,
        help="run the CairoRunner in proof mode: True or False",
    )
    parser.addoption(
        "--layout",
        choices=dir(LAYOUTS),
        default="all_cairo_instance",
        help="The layout of the Cairo AIR.",
    )
    parser.addoption(
        "--seed",
        action="store",
        default=None,
        type=int,
        help="The seed to set random with.",
    )


pytest_plugins = ["tests.fixtures.compiler", "tests.fixtures.runner"]


settings.register_profile(
    "nightly",
    deadline=None,
    max_examples=1500,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.register_profile(
    "ci",
    deadline=None,
    max_examples=100,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.register_profile(
    "dev",
    deadline=None,
    max_examples=20,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.register_profile(
    "debug",
    max_examples=20,
    verbosity=Verbosity.verbose,
    phases=[Phase.explicit, Phase.reuse, Phase.generate, Phase.target],
)
settings.load_profile(os.getenv("HYPOTHESIS_PROFILE", "default"))
logger.info(f"Using Hypothesis profile: {os.getenv('HYPOTHESIS_PROFILE', 'default')}")
