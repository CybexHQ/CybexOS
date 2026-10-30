"use strict";
// Two Qt 6.12 changes the shell's own code must not trip over.
//
// 1. Qt 6.12 hands a QML signal handler's `var` argument over as a sequence
// whenever it holds an array, at any depth (JsonCommand replies, picked
// values, delegate data). Sequences support length, indexing, map/filter,
// concat and JSON.stringify, but Array.isArray() is false for them, so a
// `Array.isArray(x) ? x : []` guard silently reads the list as empty.
// `instanceof Array` is true for both; Array.isArray keeps Node's arrays from
// other contexts working in these tests. Every check must use both.
//
// 2. QtQuick 6.12 adds a `Color` type that wins over an imported singleton of
// the same name, so `Color.popups` reads QtQuick's object. The Omarchy-style
// palette singleton (Commons/Color.qml) is reached through a qualified
// import: `import qs.Commons as Commons` and `Commons.Color`.
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "../../desktop/quickshell");

function sources(directory) {
    return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
        const file = path.join(directory, entry.name);
        if (entry.isDirectory())
            return entry.name === "i18n" ? [] : sources(file);
        return /\.(qml|js)$/.test(entry.name) ? [file] : [];
    });
}

function bareChecks(text) {
    const found = [];
    const needle = "Array.isArray(";
    for (let at = text.indexOf(needle); at >= 0; at = text.indexOf(needle, at + 1)) {
        const lineStart = text.lastIndexOf("\n", at) + 1;
        if (/^\s*(\/\/|\*)/.test(text.slice(lineStart, at)))
            continue; // a comment
        let end = at + needle.length;
        for (let depth = 1; depth > 0 && end < text.length; end++)
            depth += text[end] === "(" ? 1 : text[end] === ")" ? -1 : 0;
        const argument = text.slice(at + needle.length, end - 1).trim();
        const rest = text.slice(end, end + argument.length + 40);
        const escaped = argument.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        if (!new RegExp("^\\s*\\|\\|\\s*" + escaped + "\\s+instanceof Array").test(rest))
            found.push(text.slice(0, at).split("\n").length + ": Array.isArray(" + argument + ")");
    }
    return found;
}

test("array checks accept Qt 6.12 sequences", () => {
    const problems = sources(root).flatMap(file =>
        bareChecks(fs.readFileSync(file, "utf8")).map(line => path.relative(root, file) + ":" + line));
    assert.deepEqual(problems, []);
});

test("the scanner recognises bare and paired checks", () => {
    assert.deepEqual(bareChecks("a(Array.isArray(x) ? x : [])"), ["1: Array.isArray(x)"]);
    assert.deepEqual(bareChecks("(Array.isArray(v.list) || v.list instanceof Array)"), []);
    assert.deepEqual(bareChecks("// Array.isArray(x) is false for sequences"), []);
});

test("the shell's Color palette is always reached through a qualified import", () => {
    const bare = /(^|[^A-Za-z0-9_.])Color\.[a-zA-Z]/;
    const problems = sources(root).filter(file => file.endsWith(".qml") && !file.endsWith(path.join("Commons", "Color.qml")))
        .flatMap(file => fs.readFileSync(file, "utf8").split("\n").map((line, index) =>
            bare.test(line.replace(/\/\/.*$/, "")) ? path.relative(root, file) + ":" + (index + 1) : null))
        .filter(Boolean);
    assert.deepEqual(problems, []);
});
