// Faithful JS port of Maccy's native KeyboardLayoutFixer
// (Maccy/Actions/KeyboardLayoutFixer.swift).
//   transformFixLayout(s) == KeyboardLayoutFixer.fix(s)
//
// Direction is auto-detected: more Hebrew letters than Latin -> HE->EN,
// otherwise (incl. tie / all-Latin) -> EN->HE. Unmapped characters pass through.

// English-typed character -> Hebrew character the user intended.
var EN_TO_HE = {
  // letters lowercase
  "q": "/", "w": "'", "e": "ק", "r": "ר", "t": "א", "y": "ט", "u": "ו",
  "i": "ן", "o": "ם", "p": "פ",
  "a": "ש", "s": "ד", "d": "ג", "f": "כ", "g": "ע", "h": "י", "j": "ח",
  "k": "ל", "l": "ך",
  "z": "ז", "x": "ס", "c": "ב", "v": "ה", "b": "נ", "n": "מ", "m": "צ",
  // letters uppercase (Hebrew has no case)
  "Q": "/", "W": "'", "E": "ק", "R": "ר", "T": "א", "Y": "ט", "U": "ו",
  "I": "ן", "O": "ם", "P": "פ",
  "A": "ש", "S": "ד", "D": "ג", "F": "כ", "G": "ע", "H": "י", "J": "ח",
  "K": "ל", "L": "ך",
  "Z": "ז", "X": "ס", "C": "ב", "V": "ה", "B": "נ", "N": "מ", "M": "צ",
  // punctuation unshifted
  "`": ";", "[": "]", "]": "[",
  ";": "ף", "'": ",",
  ",": "ת", ".": "ץ", "/": ".",
  // shifted symbols that DIFFER between layouts (RTL swaps)
  "(": ")", ")": "(",
  "{": "}", "}": "{",
  "<": ">", ">": "<"
};

// Hebrew-typed character -> English character the user intended.
var HE_TO_EN = {
  // hebrew letters
  "ש": "a", "ד": "s", "ג": "d", "כ": "f", "ע": "g", "י": "h", "ח": "j",
  "ל": "k", "ך": "l",
  "ז": "z", "ס": "x", "ב": "c", "ה": "v", "נ": "b", "מ": "n", "צ": "m",
  "ק": "e", "ר": "r", "א": "t", "ט": "y", "ו": "u", "ן": "i", "ם": "o",
  "פ": "p",
  "ף": ";", "ת": ",", "ץ": ".",
  // Hebrew-block punctuation some Hebrew layouts produce on the w-key
  // instead of ASCII apostrophe/quote.
  "׳": "w",  // HEBREW PUNCTUATION GERESH
  "״": "W",  // HEBREW PUNCTUATION GERSHAYIM (shift+w)
  // hebrew layout punctuation outputs
  "/": "q", "'": "w", ";": "`",
  "]": "[", "[": "]",
  ",": "'", ".": "/",
  // shifted swaps
  "(": ")", ")": "(",
  "{": "}", "}": "{",
  "<": ">", ">": "<"
};

function countHebrew(text) {
  var n = 0;
  var chars = Array.from(text);
  for (var i = 0; i < chars.length; i++) {
    var cp = chars[i].codePointAt(0);
    if (cp >= 0x0590 && cp <= 0x05FF) { n++; }
  }
  return n;
}

function countLatin(text) {
  var n = 0;
  var chars = Array.from(text);
  for (var i = 0; i < chars.length; i++) {
    var cp = chars[i].codePointAt(0);
    if ((cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A)) { n++; }
  }
  return n;
}

function transformFixLayout(text) {
  if (text.length === 0) { return text; }
  var table = countHebrew(text) > countLatin(text) ? HE_TO_EN : EN_TO_HE;
  var out = "";
  var chars = Array.from(text);
  for (var i = 0; i < chars.length; i++) {
    var ch = chars[i];
    out += (Object.prototype.hasOwnProperty.call(table, ch) ? table[ch] : ch);
  }
  return out;
}
