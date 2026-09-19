#!/usr/bin/env python3
"""Exercise systemd's entry-token resolution and BLS plugin in a temporary tree."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class BootEntries(unittest.TestCase):
    def test_distribution_tokens(self):
        plugin = Path('/usr/lib/kernel/install.d/90-loaderentry.install')
        self.assertTrue(plugin.is_file(), 'Install systemd to run this test')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            boot = root / 'boot'
            (boot / 'loader/entries').mkdir(parents=True)
            conf = root / 'etc/kernel'
            (conf / 'qcom').mkdir(parents=True)
            (conf / 'install.conf').write_text('layout=bls\n')
            (conf / 'cmdline').write_text('root=UUID=test-root rw\n')
            (conf / 'devicetree').write_text('qcom/gaokun3.dtb\n')
            (conf / 'qcom/gaokun3.dtb').write_bytes(b'test dtb')
            kernel = boot / 'vmlinuz-test'
            kernel.write_bytes(b'test kernel')
            initrd = boot / 'initrd-test'
            initrd.write_bytes(b'test initrd')
            version = '7.2.6-gaokun3'
            for distro in ('fedora', 'ubuntu'):
                (root / 'etc/os-release').write_text(f'ID={distro}\n')
                (conf / 'entry-token').write_text(distro + '\n')
                for machine_id in ('1' * 32, '2' * 32):
                    (root / 'etc/machine-id').write_text(machine_id + '\n')
                    for mode in ('default', 'os-id'):
                        with self.subTest(distro=distro, machine_id=machine_id, mode=mode):
                            token_option = ['--entry-token=os-id'] if mode == 'os-id' else []
                            output = subprocess.check_output([
                                'kernel-install', f'--root={root}', '--json=short',
                                *token_option, 'inspect', version,
                                '/boot/vmlinuz-test',
                            ], text=True)
                            info = json.loads(output)
                            self.assertEqual(info['EntryToken'], distro)
                            self.assertTrue(info['EntryDirectory'].endswith(f'{distro}/{version}'))
                            self.assertEqual(info['MachineID'], machine_id)

                entry_dir = boot / distro / version
                entry_dir.mkdir(parents=True)
                env = dict(os.environ, KERNEL_INSTALL_LAYOUT='bls',
                           KERNEL_INSTALL_MACHINE_ID='2' * 32,
                           KERNEL_INSTALL_ENTRY_TOKEN=distro,
                           KERNEL_INSTALL_BOOT_ROOT=str(boot), BOOT_MNT=str(boot),
                           KERNEL_INSTALL_CONF_ROOT=str(conf),
                           KERNEL_INSTALL_STAGING_AREA=str(root / 'staging'),
                           KERNEL_INSTALL_VERBOSE='0')
                subprocess.run(['sh', str(plugin), 'add', version, str(entry_dir),
                                str(kernel), str(initrd)], env=env, check=True)
                entry = boot / 'loader/entries' / f'{distro}-{version}.conf'
                content = entry.read_text()
                self.assertIn(f'/{distro}/{version}/linux', content)
                self.assertIn(f'/{distro}/{version}/gaokun3.dtb', content)
                self.assertIn(f'/{distro}/{version}/initrd-test', content)
                self.assertNotIn('systemd.machine_id=', content)
                self.assertEqual((entry_dir / 'linux').read_bytes(), kernel.read_bytes())
                self.assertEqual((entry_dir / 'gaokun3.dtb').read_bytes(), b'test dtb')
                self.assertEqual((entry_dir / 'initrd-test').read_bytes(), initrd.read_bytes())

            # Removing Fedora's entry must leave Ubuntu's entry available.
            env['KERNEL_INSTALL_ENTRY_TOKEN'] = 'fedora'
            subprocess.run(['sh', str(plugin), 'remove', version,
                            str(boot / 'fedora' / version)], env=env, check=True)
            self.assertFalse((boot / 'loader/entries' / f'fedora-{version}.conf').exists())
            self.assertTrue((boot / 'loader/entries' / f'ubuntu-{version}.conf').exists())


if __name__ == '__main__':
    unittest.main()
