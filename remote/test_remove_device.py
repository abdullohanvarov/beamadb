import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from remove_device import remove, uninstall, phone_key

class RemovalTest(unittest.TestCase):
    def test_wrong_phone_never_uninstalled(self):
        with patch('remove_device.subprocess.run', return_value=subprocess.CompletedProcess([], 0, 'different-phone\n', '')) as command:
            self.assertFalse(uninstall('adb', 'transport', 'wanted-phone'))
            self.assertEqual(command.call_count, 1)

    def test_uninstall_only_confirmed_on_success(self):
        responses = [subprocess.CompletedProcess([],0,'wanted-phone\n',''), subprocess.CompletedProcess([],0,'Success\n','')]
        with patch('remove_device.subprocess.run', side_effect=responses):
            self.assertTrue(uninstall('adb', 'transport', 'wanted-phone'))

    def test_offline_removal_blocks_reinstall_and_can_finish_later(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            key = phone_key('test-identity')
            folder = base / 'phones' / key
            folder.mkdir(parents=True)
            (folder / 'desktop.json').write_text('{}')
            with patch('remove_device.Path.home', return_value=base):
                self.assertEqual(remove(base, 'test-identity', None, 'adb'), 'pending')
                self.assertFalse(folder.exists())
                marker = base / 'removed' / (key + '.json')
                self.assertEqual(json.loads(marker.read_text())['state'], 'pending')
                with patch('remove_device.uninstall', return_value=True):
                    self.assertEqual(remove(base, 'test-identity', 'usb', 'adb'), 'complete')
                self.assertEqual(json.loads(marker.read_text())['state'], 'complete')
                self.assertEqual(marker.stat().st_mode & 0o777, 0o600)
