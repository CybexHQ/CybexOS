// Display names preserve file casing and replace separators with spaces.
function label(fileName) {
    var name = String(fileName || "").split("/").pop().replace(/\.[^.]+$/, "");
    return name.replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim() || String(fileName || "");
}

var exported = { label: label };
if (typeof module !== "undefined" && module.exports)
    module.exports = exported;
