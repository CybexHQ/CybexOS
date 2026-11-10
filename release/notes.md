# Cybex OS 1.0.29

Google Chrome is now the web browser when proprietary applications are installed, in place of Brave Origin. Sign in to Chrome with your Google account and your bookmarks, passwords and history sync. Chrome keeps saved passwords in your keyring and opens straight to a window, without a first-run dialog.

The welcome guide's Connect step has a new Google account card, next to 1Password and the assistant. It opens Chrome's sign-in and shows a tick with your address once you are signed in.

Chrome adds the Claude and ChatGPT extensions on its own, so Claude Code and ChatGPT can work in your browser once you sign in to them. You can switch either off in Chrome's extensions. 1Password's extension comes along as before.

Brave Origin is now an optional install. Choose it in Software's browser picker. On a computer that had it, its bookmarks and settings are still there when you add it back. A browser no longer makes itself the default when it starts: the one you pick in Software stays your default.

Codex and Claude Code now come straight from OpenAI's and Anthropic's own releases. New versions reach beta computers within about a day of their release, and no longer wait for NixOS to build them. Codex and Claude Code no longer update themselves either: Software Update brings their new versions, like the rest of the system.

This is a source update with no new ISO. Installation, boot, physical hardware and staged-updater qualification are separate from source tests and package builds.
