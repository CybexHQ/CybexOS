#!/usr/bin/env python3
"""Keep logind's lid policy independent of an external display's DPMS state."""
import array
import math
import os
from pathlib import Path
import socket
import sys
import time


LOGIN = 'org.freedesktop.login1'
MANAGER = LOGIN + '.Manager'
OBJECT = '/org/freedesktop/login1'
# The same external connector types logind recognises, including MST paths.
# Internal eDP/LVDS/DSI panels and virtual/writeback outputs never count.
EXTERNAL = ('VGA-', 'DVI-I-', 'DVI-D-', 'DVI-A-', 'Composite-', 'SVIDEO-',
            'Component-', 'DIN-', 'DP-', 'HDMI-A-', 'HDMI-B-', 'TV-')
# Match external-monitor-toggle: cover subsecond DP retraining without keeping
# an actually unplugged, closed laptop awake for a long settling interval.
DISCONNECT_GRACE = 3.0


def notify_systemd(message, fd=None):
    address = os.environ.get('NOTIFY_SOCKET')
    if not address:
        return
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as connection:
        connection.connect('\0' + address[1:] if address.startswith('@') else address)
        rights = [] if fd is None else [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array('i', [fd]))]
        connection.sendmsg([message.encode()], rights)


def external_connected(root):
    for status in root.glob('card*-*/status'):
        connector = status.parent.name.partition('-')[2]
        if not connector.startswith(EXTERNAL):
            continue
        try:
            # Deliberately never read "enabled": DPMS off disables a connector
            # without unplugging it. Hyprland's output list is not hardware state.
            if status.read_text().strip() == 'connected':
                return True
        except FileNotFoundError:
            # A connector directory can disappear while a GPU/dock is removed.
            continue
    return False


class LidPolicy:
    """Debounce loss while already closed, never an undocked lid-close edge."""
    def __init__(self):
        self.inhibited = False
        self.lid_closed = False
        self.deadline = None

    def update(self, connected, lid_closed, now):
        closing = lid_closed and not self.lid_closed
        self.lid_closed = lid_closed
        if connected:
            self.inhibited = True
            self.deadline = None
        elif not lid_closed or closing or not self.inhibited:
            self.inhibited = False
            self.deadline = None
        else:
            if self.deadline is None:
                self.deadline = now + DISCONNECT_GRACE
            if now >= self.deadline:
                self.inhibited = False
                self.deadline = None
        return self.inhibited


class LidGuard:
    def __init__(self, bus, monitor, glib, drm_root=Path('/sys/class/drm'), inherited=None):
        self.bus, self.monitor, self.glib = bus, monitor, glib
        self.drm_root = drm_root
        self.policy = LidPolicy()
        self.inherited = inherited
        if inherited is not None:
            # Keep protection across an updater/service restart. If the output
            # vanished during the restart, grant a fresh disconnect grace.
            self.policy.inhibited = True
            self.policy.lid_closed = True
        self.fd = None
        self.timer = None
        self.failed = False
        self.loop = glib.MainLoop()
        self.login = bus.get_object(LOGIN, OBJECT)

    def reconcile(self):
        try:
            closed = bool(self.login.Get(MANAGER, 'LidClosed',
                                         dbus_interface='org.freedesktop.DBus.Properties'))
            inhibit = self.policy.update(external_connected(self.drm_root), closed, time.monotonic())
            if inhibit and self.fd is None:
                self.fd = self.login.Inhibit(
                    'handle-lid-switch', 'Cybex OS external display',
                    'External display connected (including DPMS off); 3 s disconnect grace',
                    'block', dbus_interface=MANAGER).take()
                # systemd retains a duplicate across restarts. The inherited
                # copy remains open until this replacement is acquired/stored,
                # including when logind itself (and its FIFO) has restarted.
                notify_systemd('FDSTOREREMOVE=1\nFDNAME=lid')
                notify_systemd('FDSTORE=1\nFDNAME=lid', self.fd)
                print('External display connected: inhibiting lid handling', flush=True)
            elif not inhibit and self.fd is not None:
                notify_systemd('FDSTOREREMOVE=1\nFDNAME=lid')
                os.close(self.fd)
                self.fd = None
                # logind rechecks a closed lid when it handles the inhibitor's
                # closure. Its normal PrepareForSleep/delay-inhibitor protocol
                # still runs hypridle's cybexos-session-action lock first.
                print('No external display: restoring logind lid handling', flush=True)
            if self.timer is not None:
                self.glib.source_remove(self.timer)
                self.timer = None
            if self.policy.deadline is not None:
                remaining = self.policy.deadline - time.monotonic()
                self.timer = self.glib.timeout_add(max(1, math.ceil(remaining * 1000)), self.expired)
        except Exception as error:
            self.fail(error)

    def fail(self, error):
        print(f'cybexos-lid-guard: {error}', file=sys.stderr, flush=True)
        self.failed = True
        self.loop.quit()

    def expired(self):
        self.timer = None
        # Sample again at the deadline: a reconnect may precede its udev event.
        self.reconcile()
        return False

    def drm_changed(self, _fd, condition):
        if condition & (self.glib.IO_ERR | self.glib.IO_HUP):
            self.fail('DRM event stream disconnected')
            return False
        try:
            while self.monitor.poll(timeout=0) is not None:
                pass
        except Exception as error:
            self.fail(error)
            return False
        self.reconcile()
        return not self.failed

    def lid_changed(self, _interface, changed, invalidated):
        if 'LidClosed' in changed or 'LidClosed' in invalidated:
            self.reconcile()

    def login_changed(self, _name, previous, current):
        if previous != current:
            # logind owns the inhibitor FIFO. Reacquire against its new owner
            # through a service restart, never keep a stale file descriptor.
            self.fail('logind restarted; restarting the lid guard')

    def run(self):
        # Subscribe before the initial snapshot, so hotplug/lid changes cannot
        # fall between enumeration and starting the event stream. No ACPI poll.
        self.bus.add_signal_receiver(self.lid_changed,
                                     signal_name='PropertiesChanged',
                                     dbus_interface='org.freedesktop.DBus.Properties',
                                     bus_name=LOGIN, path=OBJECT, arg0=MANAGER)
        self.bus.add_signal_receiver(self.login_changed,
                                     signal_name='NameOwnerChanged',
                                     dbus_interface='org.freedesktop.DBus',
                                     bus_name='org.freedesktop.DBus', arg0=LOGIN)
        self.monitor.start()
        self.glib.io_add_watch(self.monitor.fileno(),
                               self.glib.IO_IN | self.glib.IO_ERR | self.glib.IO_HUP,
                               self.drm_changed)
        try:
            self.reconcile()
            if self.inherited is not None:
                os.close(self.inherited)
                self.inherited = None
            if not self.failed:
                notify_systemd('READY=1')
                self.loop.run()
        finally:
            if self.fd is not None:
                os.close(self.fd)
                self.fd = None
            if self.inherited is not None:
                os.close(self.inherited)
                self.inherited = None
        return 75 if self.failed else 0


def main():
    import dbus
    from dbus.mainloop.glib import DBusGMainLoop
    from gi.repository import GLib
    import pyudev

    DBusGMainLoop(set_as_default=True)
    monitor = pyudev.Monitor.from_netlink(pyudev.Context())
    monitor.filter_by(subsystem='drm')
    inherited = None
    if (os.environ.get('LISTEN_PID') == str(os.getpid())
            and os.environ.get('LISTEN_FDS') == '1'
            and os.environ.get('LISTEN_FDNAMES') == 'lid'):
        inherited = 3
        os.set_inheritable(inherited, False)
    return LidGuard(dbus.SystemBus(), monitor, GLib, inherited=inherited).run()


if __name__ == '__main__':
    sys.exit(main())
