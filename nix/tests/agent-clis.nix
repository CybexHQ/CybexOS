# The agent CLIs Wiz drives, as Cybex OS packages them from the vendors' own
# builds: each runs, reports its pinned version, and still offers what Wiz
# uses. The vendor-updates workflow runs this before it releases an update.
# No network and no sign-in: Codex's app-server answers Wiz's `initialize`
# request; Claude Code still lists every option Wiz passes it
# (desktop/assistant/cybexos_assistant/claude.py).
#   nix build .#checks.x86_64-linux.agent-clis
{ pkgs, codex, claude-code }:
let
  handshake = pkgs.writeText "codex-app-server-handshake.py" ''
    import json, select, subprocess, sys, time
    server = subprocess.Popen([sys.argv[1], "app-server"], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, text=True)
    server.stdin.write(json.dumps({"id": 1, "method": "initialize", "params": {
        "clientInfo": {"name": "cybexos_assistant", "title": "Cybex OS Assistant", "version": "1"},
        "capabilities": {"experimentalApi": False, "requestAttestation": False}}}) + "\n")
    server.stdin.flush()
    deadline = time.monotonic() + 60
    try:
        while time.monotonic() < deadline:
            if not select.select([server.stdout], [], [], 1)[0]:
                continue
            line = server.stdout.readline()
            if not line:
                sys.exit("codex app-server exited before answering initialize")
            message = json.loads(line)
            if message.get("id") == 1:
                if "result" not in message:
                    sys.exit(f"codex app-server refused initialize: {message}")
                print("codex app-server:", json.dumps(message["result"]))
                break
        else:
            sys.exit("codex app-server did not answer initialize")
    finally:
        server.kill()
  '';
in
pkgs.runCommand "cybexos-agent-clis" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export HOME=$(mktemp -d)
  cd "$HOME"

  version=$(${codex}/bin/codex --version)
  echo "$version"
  [ "$version" = "codex-cli ${codex.version}" ]
  # Codex finds its bundled tools through the package layout.
  ${codex}/lib/codex/codex-path/rg --version
  ${codex}/lib/codex/codex-resources/bwrap --version
  python3 -I ${handshake} ${codex}/bin/codex

  # A stripped Bun executable would answer with Bun's own version instead.
  version=$(${claude-code}/bin/claude --version)
  echo "$version"
  [ "$version" = "${claude-code.version} (Claude Code)" ]
  ${claude-code}/bin/claude --help > help
  for option in --print --input-format --output-format --verbose --include-partial-messages \
      --permission-prompt-tool --append-system-prompt --model --mcp-config --disallowedTools --resume; do
    grep -q -- "$option" help || { echo "claude --help no longer lists $option" >&2; exit 1; }
  done
  # Cybex OS updates Claude Code; Claude Code does not update itself.
  grep -q DISABLE_AUTOUPDATER ${claude-code}/bin/claude

  touch $out
''
