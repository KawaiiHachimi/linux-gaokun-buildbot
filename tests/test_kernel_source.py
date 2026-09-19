#!/usr/bin/env python3
"""Check that source preparation never overwrites a mismatched or dirty tree."""
from pathlib import Path
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'scripts/lib/kernel_source.sh'


class SourcePreparation(unittest.TestCase):
    def test_existing_checkout_guards(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            def git(*args):
                return subprocess.check_output(['git', '-C', directory, *args], text=True).strip()
            git('init', '-q')
            git('config', 'user.name', 'Test')
            git('config', 'user.email', 'test@example.invalid')
            config = repo / 'arch/arm64/configs/gaokun3_defconfig'
            config.parent.mkdir(parents=True)
            config.write_text('CONFIG_TEST=y\n')
            git('add', '.')
            git('commit', '-qm', 'fixture')
            commit = git('rev-parse', 'HEAD')
            def prepare(sha):
                return subprocess.run(['bash', '-euc', '. "$1"; prepare_kernel_source "$2" "$3"',
                                       'test', str(HELPER), directory, sha], capture_output=True)
            self.assertEqual(prepare(commit).returncode, 0)
            self.assertNotEqual(prepare('0' * 40).returncode, 0)
            self.assertEqual(git('rev-parse', 'HEAD'), commit)
            config.write_text('local edit\n')
            self.assertNotEqual(prepare(commit).returncode, 0)
            self.assertEqual(config.read_text(), 'local edit\n')
            git('checkout', '--', str(config.relative_to(repo)))
            (repo / 'untracked.c').write_text('local file\n')
            self.assertNotEqual(prepare(commit).returncode, 0)
            self.assertTrue((repo / 'untracked.c').exists())


if __name__ == '__main__':
    unittest.main()
