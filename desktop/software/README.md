# Software catalogue

`sources.json` is the curated list behind **Software** and the installer's
software profiles: each app's Nixpkgs attribute, AppStream ID, category and
subcategory, plus the profiles, featured apps and display-name overrides.

`catalogue.json` and `icons/` are generated from it by
`scripts/software-catalogue` (see its header for the command). The generator:

- resolves every attribute in the repository's locked Nixpkgs and keeps only
  apps NixOS has prebuilt in cache.nixos.org, or unfree vendor downloads that
  NixOS never caches. Missing, broken and not-yet-built packages are dropped
  and listed, so a later run picks them up once NixOS has built them;
- adds Flathub AppStream metadata: name, summary, description (Flatpak
  packaging notes removed), developer, licence, brand colours, screenshot URLs
  and installs over the last 30 days, which ranks **Popular**;
- re-encodes each app's 128 px Flathub icon into `icons/<id>.png`;
- records each app's desktop file names from its NixOS output and the
  compressed download beyond the default installation, per app and per
  profile.

Regenerate before each release, after updating `flake.lock`.
`scripts/software-catalogue --check` verifies the catalogue against
`sources.json` and the icons without network access.

Screenshots are not shipped. Software loads them from Flathub's media server
when someone opens an app's page. Icons and screenshots belong to their
projects and identify the apps; names and logos remain their owners'
trademarks.
