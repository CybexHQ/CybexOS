{ config, options, lib, pkgs, modulesPath, ... }:
let
  cfg = config.cybexos;
  selected = map (name: {
    attribute = name;
    package = lib.attrByPath (lib.splitString "." name)
      (throw "Software package ${name} is unavailable in the machine's locked Nixpkgs") pkgs;
  }) cfg.software.packages;
  # Who declared each systemPackages entry, from its definition's file:
  # Software's own selections (this module), Cybex OS's vendor modules (this
  # source tree), the NixOS modules they enable, and everything else, which
  # is the machine's personal configuration and the inputs it imports.
  vendor = toString ../.. + "/";
  nixos = toString modulesPath + "/";
  origin = file:
    if file == toString ./software.nix then "software"
    else if lib.hasPrefix vendor file then "cybexos"
    else if lib.hasPrefix nixos file then "nixos"
    else "personal";
  definitions = map (definition: {
    origin = origin (toString definition.file);
    paths = map toString definition.value;
  }) options.environment.systemPackages.definitionsWithLocations;
  origins = path: lib.unique (map (definition: definition.origin)
    (builtins.filter (definition: builtins.elem path definition.paths) definitions));
in {
  options.cybexos.software.packages = lib.mkOption {
    type = lib.types.listOf (lib.types.strMatching "[A-Za-z0-9_][A-Za-z0-9_+.-]*");
    default = [];
    description = "Native package attributes selected through the staged Software interface.";
  };
  config = lib.mkIf cfg.enable {
    assertions = map (entry: {
      assertion = builtins.elem (toString entry.package) (map toString config.environment.systemPackages);
      message = "Software selection ${entry.attribute} is excluded by another systemPackages definition. Preserve that declaration and resolve the conflict explicitly.";
    }) selected;
    environment.systemPackages = map (entry: entry.package) selected;
    # Schema 1 grows only by fields: `origins` lists "software", "cybexos",
    # "nixos" and/or "personal"; `managedElsewhere` (any origin but Software)
    # stays for older readers.
    environment.etc."cybexos/software.json".text = builtins.toJSON {
      schema = 1;
      selected = cfg.software.packages;
      packages = lib.unique (map (package: let path = toString package; from = origins path; in {
        inherit path;
        name = package.pname or (lib.getName package);
        version = package.version or "";
        description = package.meta.description or "";
        attributes = map (entry: entry.attribute)
          (builtins.filter (entry: toString entry.package == path) selected);
        origins = from;
        managedElsewhere = builtins.any (value: value != "software") from;
      }) config.environment.systemPackages);
    };
  };
}
