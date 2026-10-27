import pathlib
import subprocess
import sys
import tempfile
import unittest

CHECKER = pathlib.Path("tools/check_kwrt_kernel.py").resolve()
PYTHON = sys.executable


class KernelCheckerTests(unittest.TestCase):
    def test_accepts_selected_kernel_declaration(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "kernel-6.12").write_text(
                "LINUX_VERSION-6.12 = 6.12.112\n", encoding="ascii"
            )
            result = subprocess.run(
                [PYTHON, str(CHECKER), "6.12.112", str(root)],
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_wrong_kernel_declaration(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            (root / "kernel-6.12").write_text(
                "LINUX_VERSION-6.12 = 6.12.111\n", encoding="ascii"
            )
            result = subprocess.run(
                [PYTHON, str(CHECKER), "6.12.112", str(root)],
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("6.12.111", result.stderr)


if __name__ == "__main__":
    unittest.main()
