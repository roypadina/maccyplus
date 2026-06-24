// Faithful JS port of Maccy's native TextUnwrap (Maccy/Actions/TextUnwrap.swift).
// Used by the bundled "Unwrap terminal command" package:
//   - matchesSoftWrap(s)  == TextUnwrap.isSoftWrapped(s)
//   - transformUnwrap(s)   == TextUnwrap.unwrap(s)
//
// Notes on fidelity:
//  * Swift counts characters by Unicode grapheme; we count by code point via
//    Array.from(line).length, which matches for all realistic terminal text.
//  * Foundation's `.whitespaces` set excludes newlines; `.whitespacesAndNewlines`
//    includes them. The regex classes below mirror those Unicode whitespace sets.

var MIN_WRAP_WIDTH = 40;

// Unicode whitespace WITHOUT line breaks (Foundation `.whitespaces`).
var WS = "\\t\\x20\\xA0\\u1680\\u2000-\\u200A\\u202F\\u205F\\u3000";
// Unicode whitespace WITH line breaks (Foundation `.whitespacesAndNewlines`).
var WSNL = WS + "\\n\\r\\v\\f\\u0085\\u2028\\u2029";

function normalize(text) {
  return text.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
}

function trimWhitespace(text) {
  var re = new RegExp("^[" + WS + "]+|[" + WS + "]+$", "g");
  return text.replace(re, "");
}

function trimWhitespaceAndNewlines(text) {
  var re = new RegExp("^[" + WSNL + "]+|[" + WSNL + "]+$", "g");
  return text.replace(re, "");
}

function charCount(s) {
  return Array.from(s).length;
}

function matchesSoftWrap(text) {
  var normalized = normalize(text);
  var lines = normalized.split("\n");
  if (lines.length > 0 && lines[lines.length - 1] === "") {
    lines.pop(); // trailing newline
  }
  if (lines.length < 2) { return false; }

  var interior = lines.slice(0, lines.length - 1);
  var widths = {};
  for (var i = 0; i < interior.length; i++) {
    widths[charCount(interior[i])] = true;
  }
  var keys = Object.keys(widths);
  if (keys.length !== 1) { return false; }
  var l = parseInt(keys[0], 10);
  if (!(l >= MIN_WRAP_WIDTH)) { return false; }

  var last = lines[lines.length - 1];
  if (last.length === 0) { return false; }
  if (!(charCount(last) <= l)) { return false; }
  return true;
}

function transformUnwrap(text) {
  var normalized = normalize(text);
  var result;
  if (matchesSoftWrap(normalized)) {
    result = normalized.replace(/\n/g, "");
  } else {
    result = normalized
      .split("\n")
      .map(function (line) { return trimWhitespace(line); })
      .join(" ");
  }
  return trimWhitespaceAndNewlines(result);
}
