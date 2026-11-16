"""ALFRED: the limits on one run of generator code (py_utils/func.py: G2F_GEN_MEM_MB, G2F_GEN_FILE_MB)."""
import importlib
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
_HOME = tempfile.mkdtemp()   # py_utils.llm_utils reads openai_key.txt from the current folder on import
with open(os.path.join(_HOME, "openai_key.txt"), "w") as _f:
    _f.write("none\n")
os.chdir(_HOME)


def load(mem, size):
    os.environ["G2F_GEN_MEM_MB"], os.environ["G2F_GEN_FILE_MB"] = str(mem), str(size)
    from py_utils import func
    return importlib.reload(func)


class GenLimits(unittest.TestCase):
    def run_code(self, func, code):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "g.py")
            with open(path, "w") as f:
                f.write(code)
            return func.run_cmd([sys.executable, path], timeout=60, cwd=d)

    def test_small_file_passes(self):
        func = load(2048, 1)
        status, _ = self.run_code(func, "open('a.bin', 'wb').write(b'x' * 1000)\n")
        self.assertEqual(status, func.ExecutionStatus.SUCCESS)

    def test_big_file_fails(self):
        func = load(2048, 1)
        status, msg = self.run_code(func, "f = open('a.bin', 'wb')\nfor _ in range(4): f.write(b'x' * (1 << 20))\nf.close()\n")
        self.assertNotEqual(status, func.ExecutionStatus.SUCCESS)

    def test_big_allocation_fails(self):
        func = load(512, 1)
        status, msg = self.run_code(func, "x = bytearray(1 << 30)\n")
        self.assertNotEqual(status, func.ExecutionStatus.SUCCESS)

    def test_off(self):
        func = load(0, 0)
        status, _ = self.run_code(func, "open('a.bin', 'wb').write(b'x' * (2 << 20))\n")
        self.assertEqual(status, func.ExecutionStatus.SUCCESS)


if __name__ == "__main__":
    unittest.main()
