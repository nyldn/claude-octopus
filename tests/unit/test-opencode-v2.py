#!/usr/bin/env python3
"""Exercise both OpenCode generations without auth, installs, or model calls."""
import json
import os
import signal
import time
from itertools import product
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(os.environ.get("OCTO_TEST_ROOT", Path(__file__).resolve().parents[2]))
# Import fixture code from this entry point, independently of the target repo.
FIXTURE_IMPORT_ROOT = Path(__file__).resolve().parents[1] / "fixtures"
sys.path.insert(0, str(FIXTURE_IMPORT_ROOT))

from opencode_v2.cases_1 import OpenCodeCases1
from opencode_v2.cases_2 import OpenCodeCases2
from opencode_v2.cases_3 import OpenCodeCases3
from opencode_v2.cases_4 import OpenCodeCases4
from opencode_v2.cases_5 import OpenCodeCases5

class OpenCodeCompatibility(OpenCodeCases1, OpenCodeCases2, OpenCodeCases3, OpenCodeCases4, OpenCodeCases5):
    pass


del OpenCodeCases1, OpenCodeCases2, OpenCodeCases3, OpenCodeCases4, OpenCodeCases5


if __name__ == "__main__":
    unittest.main()
