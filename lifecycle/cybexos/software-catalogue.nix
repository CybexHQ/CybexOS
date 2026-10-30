# The machine's effective package set, including personal overlays.
#
# Without `attributes`: every package, for Software's full Nixpkgs search.
# Nixpkgs deliberately contains throwing/unsupported attributes. Isolate each
# metadata evaluation rather than making a single bad package break discovery.
#
# With `attributes`: metadata for just those attribute paths (the shipped app
# catalogue, or the apps Software is about to install), plus whether this
# machine allows unfree packages. `derivations` adds each derivation path,
# for the prebuilt check; instantiating them costs more, so only on request.
{ machine, attributes ? null, derivations ? false }:
let
  pkgs = (builtins.getFlake machine).nixosConfigurations.cybexos.pkgs;
  lib = pkgs.lib;
  visit = depth: prefix: value:
    let attempt = builtins.tryEval (builtins.deepSeq result result);
        result = if lib.isDerivation value then [{
          attribute = lib.concatStringsSep "." prefix;
          name = value.pname or (lib.getName value);
          version = value.version or "";
          description = value.meta.description or "";
        }] else if depth > 0 && builtins.isAttrs value && (value.recurseForDerivations or false)
          then walk (depth - 1) prefix value else [];
    in if attempt.success then attempt.value else [];
  walk = depth: prefix: set: lib.concatMap
    (name: visit depth (prefix ++ [ name ]) set.${name})
    (builtins.filter (name: builtins.match "[A-Za-z0-9_][A-Za-z0-9_+-]*" name != null)
      (builtins.attrNames set));

  free = value: lib.all (license: license.free or true) (lib.toList (value.meta.license or [ ]));
  describe = attribute:
    let
      found = builtins.tryEval (lib.attrByPath (lib.splitString "." attribute) null pkgs);
      value = found.value;
      exists = found.success && builtins.tryEval (lib.isDerivation value) == { success = true; value = true; };
      # meta.available is false for unfree packages this machine does not
      # allow, and for broken or unsupported ones; reading it never throws.
      info = builtins.tryEval (builtins.deepSeq fields fields);
      fields = {
        pname = value.pname or (lib.getName value);
        version = value.version or "";
        unfree = !(free value);
        available = value.meta.available or true;
        broken = value.meta.broken or false;
      };
      drv = builtins.tryEval (builtins.unsafeDiscardStringContext value.drvPath);
    in { inherit attribute exists; }
      // lib.optionalAttrs exists (if info.success then info.value else { available = false; })
      // lib.optionalAttrs (exists && derivations) { drvPath = if drv.success then drv.value else null; };
in if attributes == null then walk 6 [ ] pkgs else {
  allowUnfree = pkgs.config.allowUnfree or false;
  packages = map describe attributes;
}
