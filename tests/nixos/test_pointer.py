#!/usr/bin/env python3
"""Settings -> Appearance -> Pointer: XCursor previews, the theme list,
downloads under a garbage-collector root, applying a choice, and the login
that starts with it (desktop/bin/cybexos-session)."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "desktop/quickshell/scripts"
sys.path.insert(0, str(SCRIPTS))
import pointer_xcursor  # noqa: E402

SPEC = importlib.util.spec_from_file_location("pointer", SCRIPTS / "pointer.py")
assert SPEC and SPEC.loader
pointer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pointer)

IMAGE = 0xFFFD0002


def xcursor(images):
    """An XCursor file of (nominal size, width, height, xhot, yhot, delay, BGRA byte)."""
    header, toc = 16, 12 * len(images)
    chunks, positions, offset = [], [], header + toc
    for nominal, width, height, xhot, yhot, delay, value in images:
        body = struct.pack("<9I", 36, IMAGE, nominal, 1, width, height, xhot, yhot, delay)
        body += bytes(value) * (width * height)
        positions.append(offset)
        chunks.append(body)
        offset += len(body)
    data = b"Xcur" + struct.pack("<III", header, 0x10000, len(images))
    data += b"".join(struct.pack("<III", IMAGE, image[0], position) for image, position in zip(images, positions))
    return data + b"".join(chunks)


# Opaque red pixels (B, G, R, A), and half-transparent premultiplied white.
RED = (0, 0, 255, 255)
GHOST = (128, 128, 128, 128)


def theme(base: Path, name: str, shapes=("default", "pointer", "text", "wait", "ew-resize", "not-allowed"),
          index: str | None = None) -> Path:
    directory = base / name
    (directory / "cursors").mkdir(parents=True)
    for shape in shapes:
        frames = 3 if shape == "wait" else 1
        images = [(24, 24, 24, 2, 3, 40, RED)] + [(48, 48, 48, 4, 6, 40, GHOST)] * frames
        (directory / "cursors" / shape).write_bytes(xcursor(images))
    if index is not None:
        (directory / "index.theme").write_text(index)
    return directory


def png_size(path: Path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    return struct.unpack(">II", data[16:24])


def executable(path: Path, body: str) -> Path:
    path.write_text(f"#!{sys.executable}\n{body}")
    path.chmod(0o755)
    return path


class Scratch(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.system = self.root / "system-icons"
        self.system.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls"
        self.machine = self.root / "pointers.json"
        environ = {
            "HOME": str(self.home), "XCURSOR_PATH": f"~/.icons:~/.local/share/icons:{self.system}",
            "PATH": f"{self.bin}:{os.environ.get('PATH', '')}", "XDG_DATA_HOME": "", "XDG_STATE_HOME": "",
            "XDG_CACHE_HOME": "", "HYPRLAND_INSTANCE_SIGNATURE": "",
        }
        patcher = mock.patch.dict(os.environ, environ)
        patcher.start()
        self.addCleanup(patcher.stop)
        for name in ("XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "HYPRLAND_INSTANCE_SIGNATURE"):
            del os.environ[name]
        machine = mock.patch.object(pointer, "MACHINE", str(self.machine))
        machine.start()
        self.addCleanup(machine.stop)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    @property
    def icons(self) -> Path:
        return self.home / ".local/share/icons"

    def recorder(self, name: str, status: int = 0, stdout: str = "", stderr: str = "") -> None:
        executable(self.bin / name, f"""import json, sys
with open({str(self.calls)!r}, "a") as log:
    log.write(json.dumps([{name!r}] + sys.argv[1:]) + "\\n")
sys.stdout.write({stdout!r})
sys.stderr.write({stderr!r})
sys.exit({status})
""")

    def recorded(self):
        if not self.calls.exists():
            return []
        return [json.loads(line) for line in self.calls.read_text().splitlines()]


class XCursorPreviews(Scratch):
    def test_render_draws_each_shape_at_the_preview_size_with_a_busy_strip(self) -> None:
        theme(self.system, "Plain")
        out = self.root / "out"
        entry = pointer_xcursor.render("Plain", [str(self.system)], str(out))
        self.assertEqual(entry["shapes"], ["arrow", "hand", "text", "busy", "resize", "forbidden"])
        self.assertEqual(entry["sizes"], [24, 48])
        self.assertEqual(entry["busyFrames"], 3)
        self.assertEqual(entry["busyDuration"], 200, "three 40 ms frames run at least 200 ms")
        self.assertEqual(png_size(out / "arrow.png"), (48, 48))
        self.assertEqual(png_size(out / "busy.png"), (48 * 3, 48))

    def test_premultiplied_pixels_become_straight_alpha(self) -> None:
        self.assertEqual(bytes(pointer_xcursor.straight_rgba(bytes(GHOST))), bytes((255, 255, 255, 128)))
        self.assertEqual(bytes(pointer_xcursor.straight_rgba(bytes(RED))), bytes((255, 0, 0, 255)))

    def test_older_names_and_inherited_themes_supply_missing_shapes(self) -> None:
        theme(self.system, "Base", shapes=("left_ptr", "hand2", "xterm", "watch", "sb_h_double_arrow", "crossed_circle"))
        theme(self.system, "Partial", shapes=("default",), index="[Icon Theme]\nName=Partial\nInherits=Missing, Base\n")
        entry = pointer_xcursor.render("Partial", [str(self.system)], str(self.root / "out"))
        self.assertEqual(entry["shapes"], ["arrow", "hand", "text", "busy", "resize", "forbidden"])

    def test_the_nearest_larger_size_is_chosen_and_damage_is_refused(self) -> None:
        path = self.root / "cursor"
        path.write_bytes(xcursor([(24, 24, 24, 0, 0, 0, RED), (32, 32, 32, 0, 0, 0, RED), (64, 64, 64, 0, 0, 0, RED)]))
        frames, sizes = pointer_xcursor.read_frames(str(path), 48)
        self.assertEqual((frames[0]["width"], sizes), (64, [24, 32, 64]))
        frames, _ = pointer_xcursor.read_frames(str(path), 96)
        self.assertEqual(frames[0]["width"], 64, "beyond the largest size, the largest")
        path.write_bytes(b"not a cursor")
        with self.assertRaises(pointer_xcursor.CursorError):
            pointer_xcursor.read_frames(str(path), 48)
        path.write_bytes(xcursor([(24, 24, 24, 0, 0, 0, RED)])[:60])
        with self.assertRaises(pointer_xcursor.CursorError):
            pointer_xcursor.read_frames(str(path), 24)

    def test_theme_names_are_plain(self) -> None:
        for name in ("Bibata-Modern-Classic", "phinger-cursors-dark", "volantes_cursors", "a+b.c"):
            self.assertTrue(pointer_xcursor.valid_name(name), name)
        for name in ("", "-x", ".hidden", "../etc", "two words", "a$(b)", "x" * 81, None, 7):
            self.assertFalse(pointer_xcursor.valid_name(name), name)

    def test_search_path_expands_home_and_always_includes_the_icons_folder(self) -> None:
        paths = pointer_xcursor.search_path({"HOME": "/h", "XCURSOR_PATH": "~/.icons:/sys/icons:/sys/icons"})
        self.assertEqual(paths, ["/h/.icons", "/sys/icons", "/h/.local/share/icons"])


class ThemeList(Scratch):
    def write_machine(self, downloads=None):
        self.machine.write_text(json.dumps({"v": 1, "default": {"theme": "Bibata-Modern-Ice", "size": 32},
                                            "downloads": downloads or {}}))

    def test_catalogue_themes_report_installation_downloads_and_previews(self) -> None:
        theme(self.system, "Bibata-Modern-Classic")
        theme(self.system, "Bibata-Modern-Classic-Right")
        self.write_machine({"whitesur-cursors": "/nix/store/" + "a" * 32 + "-whitesur-cursors-1"})
        listing = pointer.list_themes()
        self.assertEqual(listing["default"], {"theme": "Bibata-Modern-Ice", "size": 32})
        self.assertTrue(listing["downloads"])
        themes = {entry["id"]: entry for entry in listing["themes"]}
        classic = themes["Bibata-Modern-Classic"]
        self.assertEqual((classic["source"], classic["installed"], classic["leftInstalled"]), ("bundled", True, True))
        self.assertTrue(classic["previews"]["arrow"].endswith("assets/pointers/previews/Bibata-Modern-Classic/arrow.png"))
        self.assertTrue(os.path.isfile(classic["previews"]["arrow"]), "catalogue previews ship with the shell")
        self.assertFalse(themes["Bibata-Modern-Ice"]["installed"])
        whitesur = themes["WhiteSur-cursors"]
        self.assertEqual((whitesur["source"], whitesur["installed"], whitesur["downloadable"]), ("download", False, True))
        self.assertFalse(themes["Hackneyed"]["downloadable"], "no store path on this machine")
        self.assertNotIn("Bibata-Modern-Classic-Right", themes, "a left-handed variant is not a theme of its own")

    def test_themes_outside_the_catalogue_are_yours_or_the_systems_with_cached_previews(self) -> None:
        theme(self.icons, "MyCursors", index="[Icon Theme]\nName=My Cursors\n")
        theme(self.system, "OtherPackage")
        (self.system / "hicolor").mkdir()
        (self.system / "default").mkdir()
        theme(self.system, "bad name")
        listing = pointer.list_themes()
        self.assertFalse(listing["downloads"], "no machine record, as in a source-tree run")
        extras = {entry["id"]: entry for entry in listing["themes"] if entry["source"] in ("yours", "system")}
        self.assertEqual(set(extras), {"MyCursors", "OtherPackage"})
        self.assertEqual((extras["MyCursors"]["source"], extras["MyCursors"]["name"]), ("yours", "My Cursors"))
        self.assertEqual(extras["OtherPackage"]["source"], "system")
        arrow = Path(extras["MyCursors"]["previews"]["arrow"])
        self.assertTrue(arrow.is_file())
        self.assertTrue(str(arrow).startswith(str(self.home / ".cache/cybexos/pointer-previews/MyCursors-")))
        first = arrow.stat().st_mtime_ns
        pointer.list_themes()
        self.assertEqual(arrow.stat().st_mtime_ns, first, "drawn once until the theme changes")

    def test_a_damaged_machine_record_falls_back(self) -> None:
        self.machine.write_text(json.dumps({"default": {"theme": "x y", "size": 4096},
                                            "downloads": {"hackneyed": "/tmp/evil", "../x": "/nix/store/" + "b" * 32 + "-x"}}))
        default, downloads, configured = pointer.machine()
        self.assertEqual(default, pointer.FALLBACK_DEFAULT)
        self.assertEqual(downloads, {})
        self.assertTrue(configured)


class Downloads(Scratch):
    def setUp(self) -> None:
        super().setUp()
        # A stand-in store: download() checks the path's shape and contents,
        # and nix-store itself is a recorder that makes the root.
        self.store = self.root / "store" / ("c" * 32 + "-phinger-cursors-2.2")
        for name in ("phinger-cursors-dark", "phinger-cursors-dark-left", "phinger-cursors-light",
                     "phinger-cursors-light-left"):
            theme(self.store / "share/icons", name)
        self.machine.write_text(json.dumps({"v": 1, "downloads": {"phinger-cursors": str(self.store)}}))
        patcher = mock.patch.object(pointer, "STORE_PATH", __import__("re").compile(r"^/.+$"))
        patcher.start()
        self.addCleanup(patcher.stop)
        nix = mock.patch.object(pointer, "nix_store", lambda: str(self.bin / "nix-store"))
        nix.start()
        self.addCleanup(nix.stop)

    def fake_nix_store(self, fail: str = "") -> None:
        executable(self.bin / "nix-store", f"""import json, os, sys
with open({str(self.calls)!r}, "a") as log:
    log.write(json.dumps(["nix-store"] + sys.argv[1:]) + "\\n")
if {fail!r}:
    sys.stderr.write({fail!r} + "\\n")
    sys.exit(1)
assert sys.argv[1:2] == ["--realise"] and sys.argv[3:4] == ["--add-root"], sys.argv
os.symlink(sys.argv[2], sys.argv[4])
print(sys.argv[2])
""")

    def test_download_substitutes_under_a_root_and_links_every_variant(self) -> None:
        self.fake_nix_store()
        theme(self.icons, "phinger-cursors-light")  # the person's own copy
        self.assertEqual(pointer.download("phinger-cursors-dark"), {"success": True})
        root = self.home / ".local/state/cybexos/pointer/roots/phinger-cursors"
        self.assertEqual(self.recorded(), [["nix-store", "--realise", str(self.store), "--add-root", str(root)]])
        self.assertEqual(os.readlink(root), str(self.store))
        for name in ("phinger-cursors-dark", "phinger-cursors-dark-left", "phinger-cursors-light-left"):
            self.assertEqual(os.readlink(self.icons / name), str(root / "share/icons" / name))
            self.assertTrue(pointer.managed(name))
        self.assertFalse((self.icons / "phinger-cursors-light").is_symlink(), "a name already taken stays the person's")
        themes = {entry["id"]: entry for entry in pointer.list_themes()["themes"]}
        self.assertTrue(themes["phinger-cursors-dark"]["installed"] and themes["phinger-cursors-dark"]["removable"])
        self.assertTrue(themes["phinger-cursors-dark"]["leftInstalled"])
        self.assertFalse(themes["phinger-cursors-light"]["removable"])

    def test_remove_takes_only_its_own_links_and_the_root(self) -> None:
        self.fake_nix_store()
        theme(self.icons, "phinger-cursors-light")
        pointer.download("phinger-cursors-dark")
        self.assertEqual(pointer.remove("phinger-cursors-light"), {"success": True})
        self.assertFalse(os.path.lexists(self.icons / "phinger-cursors-dark"))
        self.assertFalse(os.path.lexists(self.icons / "phinger-cursors-dark-left"))
        self.assertTrue((self.icons / "phinger-cursors-light" / "cursors").is_dir())
        self.assertFalse(os.path.lexists(self.home / ".local/state/cybexos/pointer/roots/phinger-cursors"))

    def test_a_failed_substitution_says_why_and_links_nothing(self) -> None:
        self.fake_nix_store(fail="error: path '/nix/store/x' is required, but there is no substituter that can build it")
        with self.assertRaisesRegex(pointer.PointerError, r"^Could not download Phinger Dark\. Check the internet") as caught:
            pointer.download("phinger-cursors-dark")
        self.assertRegex(caught.exception.detail, "^error: path .* no substituter")
        self.assertFalse(self.icons.exists())

    def test_only_catalogue_downloads_with_a_store_path_are_fetched(self) -> None:
        self.fake_nix_store()
        self.assertEqual(pointer.download("Bibata-Modern-Classic"), {"success": True}, "bundled: nothing to fetch")
        with self.assertRaisesRegex(pointer.PointerError, "cannot be downloaded"):
            pointer.download("Hackneyed")
        with self.assertRaisesRegex(pointer.PointerError, "not in the pointer catalogue"):
            pointer.download("../../etc")
        with self.assertRaisesRegex(pointer.PointerError, "part of Cybex OS"):
            pointer.remove("Adwaita")
        self.assertEqual(self.recorded(), [])

    def test_the_command_line_reports_json(self) -> None:
        self.fake_nix_store(fail="error: unable to download 'https://cache.nixos.org/x.narinfo': Couldn't resolve host name")
        with mock.patch("builtins.print") as printed:
            status = pointer.main(["pointer.py", "download", "phinger-cursors-dark"])
        self.assertEqual(status, 1)
        report = json.loads(printed.call_args.args[0])
        self.assertFalse(report["success"])
        self.assertEqual(report["error"], "Could not download Phinger Dark. Check the internet connection and try again.")
        self.assertIn("Couldn't resolve host name", report["detail"])


class Apply(Scratch):
    def setUp(self) -> None:
        super().setUp()
        theme(self.system, "Bibata-Modern-Classic")
        for name in ("hyprctl", "gsettings", "dbus-update-activation-environment"):
            self.recorder(name, stdout="ok\n" if name == "hyprctl" else "")
        os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = "test"

    def session(self) -> Path:
        return self.home / ".local/state/cybexos/pointer/session.env"

    def test_apply_reaches_hyprland_gtk_the_environment_and_the_next_login(self) -> None:
        report = pointer.apply("Bibata-Modern-Classic", "48", True)
        self.assertTrue(report["success"], report)
        self.assertEqual(self.recorded(), [
            ["hyprctl", "setcursor", "Bibata-Modern-Classic", "48"],
            ["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", "Bibata-Modern-Classic"],
            ["gsettings", "set", "org.gnome.desktop.interface", "cursor-size", "48"],
            ["dbus-update-activation-environment", "--systemd", "XCURSOR_THEME=Bibata-Modern-Classic", "XCURSOR_SIZE=48"],
        ])
        self.assertEqual(self.session().read_text(), "XCURSOR_THEME=Bibata-Modern-Classic\nXCURSOR_SIZE=48\n")
        self.assertTrue(pointer.apply("Bibata-Modern-Classic", "24", False)["success"])
        self.assertFalse(self.session().exists(), "back to the installation's own: nothing to tell the next login")

    def test_a_failing_step_is_reported_and_the_others_still_run(self) -> None:
        self.recorder("gsettings", status=1, stderr="No such schema\n")
        report = pointer.apply("Bibata-Modern-Classic", "32", True)
        self.assertFalse(report["success"])
        self.assertEqual(report["error"], "gsettings: No such schema")
        self.assertEqual(report["steps"]["hyprland"], "ok")
        self.assertEqual(report["steps"]["environment"], "ok")
        self.assertTrue(self.session().exists())

    def test_names_sizes_and_missing_themes_are_refused(self) -> None:
        for theme_name, size, reason in (("a;b", "24", "name"), ("Bibata-Modern-Classic", "8", "16 to 128"),
                                         ("Bibata-Modern-Classic", "x", "16 to 128"), ("Absent", "24", "not installed")):
            with self.assertRaisesRegex(pointer.PointerError, reason):
                pointer.apply(theme_name, size, True)
        self.assertEqual(self.recorded(), [])


class Session(Scratch):
    """cybexos-session takes only the two variables, with plain values."""

    def run_session(self, record: str | None):
        state = self.home / ".local/state/cybexos/pointer"
        if record is not None:
            state.mkdir(parents=True)
            (state / "session.env").write_text(record)
        environment = self.root / "environment"
        executable(self.bin / "Hyprland", f"""import json, os
with open({str(environment)!r}, "w") as out:
    json.dump({{k: os.environ.get(k) for k in ("XCURSOR_THEME", "XCURSOR_SIZE", "LD_PRELOAD")}}, out)
""")
        self.recorder("systemctl")
        env = {"HOME": str(self.home), "PATH": os.environ["PATH"], "XCURSOR_THEME": "Bibata-Modern-Classic",
               "XCURSOR_SIZE": "24"}
        result = subprocess.run(["bash", str(ROOT / "desktop/bin/cybexos-session")], env=env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(environment.read_text())

    def test_the_saved_pointer_starts_hyprland(self) -> None:
        self.assertEqual(self.run_session("XCURSOR_THEME=WhiteSur-cursors\nXCURSOR_SIZE=48"),
                         {"XCURSOR_THEME": "WhiteSur-cursors", "XCURSOR_SIZE": "48", "LD_PRELOAD": None})

    def test_without_a_record_the_installation_default_stays(self) -> None:
        self.assertEqual(self.run_session(None),
                         {"XCURSOR_THEME": "Bibata-Modern-Classic", "XCURSOR_SIZE": "24", "LD_PRELOAD": None})

    def test_anything_else_in_the_record_is_ignored(self) -> None:
        record = ("LD_PRELOAD=/tmp/x.so\nXCURSOR_THEME=$(touch /tmp/pwned)\nXCURSOR_SIZE=4096\n"
                  "XCURSOR_THEME=bad name\nXCURSOR_SIZE=09\n")
        self.assertEqual(self.run_session(record),
                         {"XCURSOR_THEME": "Bibata-Modern-Classic", "XCURSOR_SIZE": "24", "LD_PRELOAD": None})


if __name__ == "__main__":
    unittest.main()
