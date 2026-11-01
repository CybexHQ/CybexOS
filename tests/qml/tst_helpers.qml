import QtQuick
import QtTest
import "../../desktop/quickshell/Common/Format.js" as Format
import "../../desktop/quickshell/Common/LayoutHelpers.js" as Layout
import "../../desktop/quickshell/Common/SysInfoHelpers.js" as SysInfo
import "../../desktop/quickshell/Common/T3CodeHelpers.js" as T3
import "../../desktop/quickshell/Common/UpdatesHelpers.js" as Updates

Item {
    TestCase {
        name: "QmlJavaScriptRuntime"

        // Qt's own JavaScript engine, not only Node, must accept these patterns.
        function test_release_note_items() {
            const notes = "# Cybex OS 1.0.1\n\nThe first published release.\n\n"
                + "- **Keyless releases.** A published GitHub release of\n  `CybexHQ/CybexOS`, see\n"
                + "  [the guide](https://example.com).\n- *Health* judges changes; xps_speaker_tuning and 2 * 3 stay.";
            const result = Updates.noteItems(notes, 10);
            compare(result.items.length, 3);
            compare(result.items[1], "Keyless releases. A published GitHub release of CybexHQ/CybexOS, see the guide.");
            compare(result.items[2], "Health judges changes; xps_speaker_tuning and 2 * 3 stay.");
            compare(result.more, false);
        }

        function test_format_boundaries() {
            compare(Format.clamp01(-0.1), 0);
            compare(Format.clamp01(1.1), 1);
            compare(Format.mmss(125.9), "2:05");
            compare(Format.mmss(Number.NaN), "0:00");
        }

        function test_layout_move_contract() {
            const result = Layout.moveWidget({
                left: [{ id: "a", on: true }, { id: "b", on: true }],
                center: [{ id: "clock", on: true }],
                right: []
            }, "left", "a", "center", 1);
            verify(result !== null);
            compare(result.col, "center");
            compare(result.idx, 1);
            compare(result.mods.left[0].id, "b");
            compare(result.mods.center[1].id, "a");
        }

        function test_t3_diff_is_bounded() {
            const rendered = T3.truncateDiff("line\n".repeat(3000), 100000, 2000);
            verify(rendered.truncated);
            verify(rendered.text.length <= 100000);
            verify(rendered.text.split("\n").length <= 2000);
        }

        function test_sysinfo_parsers_match_the_qml_javascript_runtime() {
            const before = SysInfo.parseCpuStat(
                "cpu 100 0 50 100 0 10 10 0 500 200\n");
            const after = SysInfo.parseCpuStat(
                "cpu 140 5 70 125 0 15 15 0 900 600\n");
            compare(SysInfo.cpuUsage(before, after), 75);

            const disk = SysInfo.parseDf(
                "Type 1B-blocks Used Avail Use% Mounted on\n"
                + "btrfs 1024 512 512 50% /\n");
            verify(disk !== null);
            compare(disk.type, "btrfs");
            compare(SysInfo.formatIecBytes(disk.totalBytes), "1 KiB");
            compare(SysInfo.formatUptime(90060), "1d 1h 1m");
        }
    }
}
