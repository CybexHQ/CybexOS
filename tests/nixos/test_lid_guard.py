"""DRM fixtures and real inhibitor FDs; no host lid, DPMS or suspend changes."""
import importlib.util
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('lid_guard', ROOT / 'desktop/power/lid_guard.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)


class DRMTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='cybexos-lid-drm-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def connector(self, name, status='connected', enabled='disabled'):
        path = self.root / name
        path.mkdir(exist_ok=True)
        (path / 'status').write_text(status + '\n')
        (path / 'enabled').write_text(enabled + '\n')
        return path

    def test_dpms_off_and_compositor_disabled_outputs_still_count(self):
        output = self.connector('card1-DP-1')
        for enabled in ('enabled', 'disabled'):
            (output / 'enabled').write_text(enabled)
            self.assertTrue(guard.external_connected(self.root))
        (output / 'enabled').unlink()
        self.assertTrue(guard.external_connected(self.root))

    def test_internal_and_virtual_panels_never_count(self):
        for name in ('eDP-1', 'LVDS-1', 'DSI-1', 'Virtual-1', 'Writeback-1', 'Unknown-1'):
            self.connector('card0-' + name, enabled='enabled')
        self.assertFalse(guard.external_connected(self.root))

    def test_multi_gpu_mst_and_hdmi_connectors(self):
        self.connector('card0-eDP-1', enabled='enabled')
        for name in ('card1-DP-2-1', 'card2-HDMI-A-1', 'card3-DVI-D-1', 'card4-VGA-1'):
            with self.subTest(name=name):
                output = self.connector(name)
                self.assertTrue(guard.external_connected(self.root))
                (output / 'status').write_text('disconnected\n')
                self.assertFalse(guard.external_connected(self.root))

    def test_only_connected_status_counts(self):
        output = self.connector('card0-DP-1')
        for state in ('disconnected', 'unknown', ''):
            (output / 'status').write_text(state)
            self.assertFalse(guard.external_connected(self.root))
        (output / 'status').unlink()
        self.assertFalse(guard.external_connected(self.root))


class PolicyTests(unittest.TestCase):
    def test_connected_closed_lid_remains_inhibited_indefinitely(self):
        policy = guard.LidPolicy()
        for now in (0, 60, 360, 600, 1800, 100000):
            self.assertTrue(policy.update(True, True, now))
            self.assertIsNone(policy.deadline)

    def test_subsecond_dropouts_do_not_release_lid_inhibitor(self):
        policy = guard.LidPolicy()
        policy.update(True, True, 0)
        for now in (60, 360, 600):
            self.assertTrue(policy.update(False, True, now))
            self.assertTrue(policy.update(False, True, now + 0.3))
            self.assertTrue(policy.update(True, True, now + 0.8))
            self.assertIsNone(policy.deadline)

    def test_disconnect_expires_after_three_seconds_even_with_event_churn(self):
        policy = guard.LidPolicy()
        policy.update(True, True, 0)
        for now in (10, 10.01, 10.5, 11, 12, 12.999):
            self.assertTrue(policy.update(False, True, now))
            self.assertEqual(policy.deadline, 13)
        self.assertFalse(policy.update(False, True, 13))
        self.assertFalse(policy.update(False, True, 100))
        self.assertIsNone(policy.deadline)

    def test_reconnection_starts_a_new_grace_period_for_the_next_dropout(self):
        policy = guard.LidPolicy()
        policy.update(True, True, 0)
        policy.update(False, True, 1)
        policy.update(True, True, 3.9)
        self.assertTrue(policy.update(False, True, 4))
        self.assertEqual(policy.deadline, 7)
        self.assertTrue(policy.update(False, True, 6.99))
        self.assertFalse(policy.update(False, True, 7))

    def test_undocked_lid_close_is_immediate_including_after_unplugging(self):
        for connected_before in (False, True):
            policy = guard.LidPolicy()
            policy.update(connected_before, False, 0)
            self.assertFalse(policy.update(False, True, 0.1))
            self.assertIsNone(policy.deadline)

    def test_opening_lid_cancels_a_pending_disconnect(self):
        policy = guard.LidPolicy()
        policy.update(True, True, 0)
        policy.update(False, True, 1)
        self.assertFalse(policy.update(False, False, 2))
        self.assertIsNone(policy.deadline)
        self.assertFalse(policy.update(False, True, 2.1))

    def test_starting_undocked_does_not_inhibit_lid_handling(self):
        for closed in (False, True):
            self.assertFalse(guard.LidPolicy().update(False, closed, 0))


class GuardTests(unittest.TestCase):
    def setUp(self):
        environment = patch.dict(os.environ, {'NOTIFY_SOCKET': ''})
        environment.start()
        self.addCleanup(environment.stop)
        self.temp = tempfile.TemporaryDirectory(prefix='cybexos-lid-guard-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / 'card1-DP-1'
        self.output.mkdir()
        (self.output / 'enabled').write_text('disabled')
        self.manager = Mock()
        self.manager.Get.return_value = True
        self.bus = Mock()
        self.bus.get_object.return_value = self.manager
        self.monitor = Mock()
        self.monitor.poll.return_value = None
        self.glib = Mock(IO_IN=1, IO_ERR=8, IO_HUP=16)
        self.service = guard.LidGuard(self.bus, self.monitor, self.glib, self.root)
        self.manager.Inhibit.side_effect = self.inhibit
        self.addCleanup(self.close_inhibitor)

    def inhibit(self, *args, **kwargs):
        read, write = os.pipe()
        self.addCleanup(os.close, read)
        return SimpleNamespace(take=lambda: write)

    def close_inhibitor(self):
        if self.service.fd is not None:
            os.close(self.service.fd)
            self.service.fd = None

    def reconcile(self, now, status='connected'):
        (self.output / 'status').write_text(status)
        with patch.object(guard.time, 'monotonic', return_value=now):
            self.service.reconcile()

    def test_only_low_level_lid_handling_is_inhibited(self):
        self.reconcile(0)
        self.manager.Inhibit.assert_called_once_with(
            'handle-lid-switch', 'Cybex OS external display',
            'External display connected (including DPMS off); 3 s disconnect grace',
            'block', dbus_interface=guard.MANAGER)
        self.glib.timeout_add.assert_not_called()
        self.reconcile(600)
        self.manager.Inhibit.assert_called_once()
        self.manager.Suspend.assert_not_called()

    def test_timer_resamples_drm_before_releasing_real_inhibitor_fd(self):
        self.reconcile(0)
        fd = self.service.fd
        self.reconcile(1, 'disconnected')
        self.assertEqual(self.glib.timeout_add.call_args.args[0], 3000)
        os.fstat(fd)
        # The return uevent has not arrived yet, but sysfs is already connected.
        (self.output / 'status').write_text('connected')
        with patch.object(guard.time, 'monotonic', return_value=4):
            self.assertFalse(self.service.expired())
        os.fstat(fd)
        self.assertIsNone(self.service.timer)
        self.assertIsNone(self.service.policy.deadline)

    def test_sustained_disconnect_closes_the_fd_for_logind_to_recheck(self):
        self.reconcile(0)
        fd = self.service.fd
        self.reconcile(1, 'disconnected')
        self.reconcile(2, 'disconnected')
        self.assertEqual(self.glib.timeout_add.call_args.args[0], 2000)
        with patch.object(guard.time, 'monotonic', return_value=4):
            self.service.expired()
        with self.assertRaises(OSError):
            os.fstat(fd)
        self.assertIsNone(self.service.fd)
        self.manager.Suspend.assert_not_called()

    def test_lid_open_signal_rechecks_and_cancels_grace(self):
        self.reconcile(0)
        self.reconcile(1, 'disconnected')
        self.manager.Get.return_value = False
        self.service.lid_changed(guard.MANAGER, {'LidClosed': False}, [])
        self.assertIsNone(self.service.fd)
        self.assertIsNone(self.service.timer)
        self.assertIsNone(self.service.policy.deadline)

    def test_failed_stream_exits_instead_of_leaving_a_permanent_inhibitor(self):
        self.assertFalse(self.service.drm_changed(0, self.glib.IO_HUP))
        self.assertTrue(self.service.failed)
        self.service.loop.quit.assert_called_once()

    def test_restart_of_logind_invalidates_its_inhibitor(self):
        self.service.login_changed(guard.LOGIN, ':1.2', ':1.3')
        self.assertTrue(self.service.failed)
        self.service.loop.quit.assert_called_once()

    def test_initialization_and_exit_clean_up_the_inhibitor(self):
        (self.output / 'status').write_text('connected')
        self.service.loop.run.side_effect = lambda: self.service.loop.quit()
        with patch.dict(os.environ, {'NOTIFY_SOCKET': ''}):
            self.assertEqual(self.service.run(), 0)
        self.assertIsNone(self.service.fd)
        self.monitor.start.assert_called_once()
        self.assertEqual(self.bus.add_signal_receiver.call_count, 2)


if __name__ == '__main__':
    unittest.main()
