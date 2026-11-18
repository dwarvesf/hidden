// scripts/release-helper.swift : the release jobs bash does badly.
//
//   verify  <file> <sig-b64> <pubkey-b64>       Ed25519 check. Exit 0 VALID, 1 INVALID, 2 bad input.
//   item    --version <build> --short <ver> --min-os <ver> --notes <file> --url <url>
//           --length <n> --sig <b64> --pubdate <rfc822> --link <url>
//                                               print the new appcast <item> text.
//   appcast --prior <xml> --item <file> --out <xml>
//                                               prepend the item; every prior item stays byte-identical.
//                                               Exit 1 on a version collision, 2 on an unexpected feed shape.
//   sigs    <appcast> <out-file>                one "version TAB short TAB url TAB length TAB signature"
//                                               line per item, file mode 600.
//
// Run as `swift scripts/release-helper.swift ...` or compile once with swiftc.
import CryptoKit
import Foundation

func fail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write(("release-helper: " + message + "\n").data(using: .utf8)!)
    exit(code)
}

func readText(_ path: String) -> String {
    guard let data = FileManager.default.contents(atPath: path) else { fail(2, "cannot read \(path)") }
    guard let text = String(data: data, encoding: .utf8) else { fail(2, "\(path) is not UTF-8") }
    return text
}

func options(_ args: ArraySlice<String>, _ names: [String]) -> [String: String] {
    var out: [String: String] = [:]
    var it = args.makeIterator()
    while let key = it.next() {
        guard key.hasPrefix("--"), names.contains(String(key.dropFirst(2))) else { fail(2, "unknown option \(key)") }
        guard let value = it.next() else { fail(2, "\(key) needs a value") }
        out[String(key.dropFirst(2))] = value
    }
    for name in names where out[name] == nil { fail(2, "missing --\(name)") }
    return out
}

// MARK: feed parsing

let itemOpen = "        <item>"
let itemClose = "        </item>"

struct Item {
    let range: Range<String.Index>   // from the start of the <item> line to the end of the </item> line
    var text: Substring
}

/// Find each item as the lines that are exactly `        <item>` and `        </item>`, outside CDATA.
/// Refuses (exit 2) a feed whose shape it would have to guess at.
func items(in feed: String, name: String) -> [Item] {
    if feed.contains("\r") { fail(2, "\(name): CR bytes (CRLF line endings) are not supported") }
    var found: [Item] = []
    var inCDATA = false
    var start: String.Index?
    var lineStart = feed.startIndex
    while lineStart < feed.endIndex {
        let lineEnd = feed[lineStart...].firstIndex(of: "\n").map { feed.index(after: $0) } ?? feed.endIndex
        let line = feed[lineStart..<lineEnd]
        let bare = line.hasSuffix("\n") ? line.dropLast() : line
        if !inCDATA {
            if bare == itemOpen {
                if start != nil { fail(2, "\(name): <item> opened twice without </item>") }
                start = lineStart
            } else if bare == itemClose {
                guard let s = start else { fail(2, "\(name): </item> without <item>") }
                found.append(Item(range: s..<lineEnd, text: feed[s..<lineEnd]))
                start = nil
            } else if outsideCDATA(bare).contains("<item") || outsideCDATA(bare).contains("</item") {
                fail(2, "\(name): an <item> tag at an unexpected indent: \(bare.trimmingCharacters(in: .whitespaces))")
            }
        }
        inCDATA = cdataStateAfter(line, startingIn: inCDATA)
        lineStart = lineEnd
    }
    if start != nil { fail(2, "\(name): <item> never closed") }
    if inCDATA { fail(2, "\(name): CDATA never closed") }
    return found
}

/// The text of one line that is outside CDATA, assuming the line starts outside CDATA.
func outsideCDATA(_ line: Substring) -> String {
    var out = ""
    var rest = line
    while let open = rest.range(of: "<![CDATA[") {
        out += rest[..<open.lowerBound]
        rest = rest[open.upperBound...]
        guard let close = rest.range(of: "]]>") else { return out }
        rest = rest[close.upperBound...]
    }
    return out + rest
}

func cdataStateAfter(_ line: Substring, startingIn inside: Bool) -> Bool {
    var inside = inside
    var rest = line
    while true {
        let marker = inside ? "]]>" : "<![CDATA["
        guard let hit = rest.range(of: marker) else { return inside }
        inside.toggle()
        rest = rest[hit.upperBound...]
    }
}

/// Item text with every CDATA section removed, so release notes can never fake a field.
func stripCDATA(_ text: Substring) -> String {
    var out = ""
    var rest = text
    while let open = rest.range(of: "<![CDATA[") {
        out += rest[..<open.lowerBound]
        rest = rest[open.upperBound...]
        guard let close = rest.range(of: "]]>") else { return out }
        rest = rest[close.upperBound...]
    }
    return out + rest
}

func element(_ name: String, in text: String) -> String? {
    guard let open = text.range(of: "<\(name)>"),
          let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex) else { return nil }
    return String(text[open.upperBound..<close.lowerBound])
}

func enclosureAttribute(_ name: String, in text: String) -> String? {
    guard let enc = text.range(of: "<enclosure ") else { return nil }
    let tail = text[enc.upperBound...]
    guard let end = tail.range(of: ">") else { return nil }
    let tag = " " + tail[..<end.lowerBound]
    guard let attr = tag.range(of: " \(name)=\""),
          let close = tag[attr.upperBound...].firstIndex(of: "\"") else { return nil }
    return String(tag[attr.upperBound..<close])
}

/// Sparkle-style numeric compare of dotted version strings ("10" > "9", "1.10" > "1.9").
func compareVersions(_ a: String, _ b: String) -> Int {
    let pa = a.split(separator: ".").map { Int($0) ?? -1 }
    let pb = b.split(separator: ".").map { Int($0) ?? -1 }
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
        if x != y { return x < y ? -1 : 1 }
    }
    return 0
}

func xmlEscape(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
}

func requireMatch(_ value: String, _ pattern: String, _ what: String) {
    if value.range(of: pattern, options: .regularExpression) == nil { fail(2, "\(what) '\(value)' does not match \(pattern)") }
}

// MARK: subcommands

let args = CommandLine.arguments
guard args.count >= 2 else { fail(2, "usage: release-helper verify|item|appcast|sigs ...") }

switch args[1] {
case "verify":
    guard args.count == 5,
          let data = FileManager.default.contents(atPath: args[2]),
          let sig = Data(base64Encoded: args[3]),
          let pubRaw = Data(base64Encoded: args[4]),
          let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubRaw) else {
        print("release-helper verify: bad input"); exit(2)
    }
    let ok = pub.isValidSignature(sig, for: data)
    print(ok ? "VALID" : "INVALID")
    exit(ok ? 0 : 1)

case "item":
    let o = options(args.dropFirst(2), ["version", "short", "min-os", "notes", "url", "length", "sig", "pubdate", "link"])
    requireMatch(o["version"]!, "^[0-9]+(\\.[0-9]+)*$", "--version")
    requireMatch(o["short"]!, "^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", "--short")
    requireMatch(o["min-os"]!, "^[0-9]+(\\.[0-9]+)*$", "--min-os")
    requireMatch(o["length"]!, "^[0-9]+$", "--length")
    requireMatch(o["sig"]!, "^[A-Za-z0-9+/]+={0,2}$", "--sig")
    requireMatch(o["url"]!, "^https://[A-Za-z0-9./_-]+$", "--url")
    requireMatch(o["link"]!, "^https://[A-Za-z0-9./_-]+$", "--link")
    requireMatch(o["pubdate"]!, "^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$", "--pubdate")
    var notes = readText(o["notes"]!)
    if notes.contains("]]>") { fail(2, "notes contain ]]>, which would end the CDATA") }
    if notes.contains("<item") || notes.contains("</item") { fail(2, "notes contain an <item> tag") }
    if notes.contains("\r") { fail(2, "notes contain CR bytes") }
    while notes.hasSuffix("\n") { notes.removeLast() }
    if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fail(2, "notes are empty") }
    let short = o["short"]!
    print("""
            <item>
                <title>Version \(short)</title>
                <pubDate>\(o["pubdate"]!)</pubDate>
                <sparkle:version>\(o["version"]!)</sparkle:version>
                <sparkle:shortVersionString>\(short)</sparkle:shortVersionString>
                <sparkle:minimumSystemVersion>\(o["min-os"]!)</sparkle:minimumSystemVersion>
                <sparkle:fullReleaseNotesLink>\(xmlEscape(o["link"]!))</sparkle:fullReleaseNotesLink>
                <description><![CDATA[
    \(notes)
    ]]></description>
                <enclosure url="\(xmlEscape(o["url"]!))" sparkle:edSignature="\(o["sig"]!)" length="\(o["length"]!)" type="application/octet-stream"/>
            </item>
    """)

case "appcast":
    let o = options(args.dropFirst(2), ["prior", "item", "out"])
    let prior = readText(o["prior"]!)
    let newItemText = readText(o["item"]!)
    let priorItems = items(in: prior, name: "prior appcast")
    if priorItems.isEmpty { fail(2, "prior appcast has no items; refusing to start a feed from nothing") }
    let newItems = items(in: newItemText, name: "new item")
    guard newItems.count == 1, newItems[0].range.lowerBound == newItemText.startIndex,
          newItems[0].range.upperBound == newItemText.endIndex else { fail(2, "new item file must hold exactly one item and nothing else") }
    let newFields = stripCDATA(newItems[0].text)
    guard let newBuild = element("sparkle:version", in: newFields),
          let newShort = element("sparkle:shortVersionString", in: newFields) else { fail(2, "new item lacks sparkle:version or shortVersionString") }
    for item in priorItems {
        let fields = stripCDATA(item.text)
        guard let build = element("sparkle:version", in: fields),
              let short = element("sparkle:shortVersionString", in: fields) else { fail(2, "a prior item lacks sparkle:version or shortVersionString") }
        if compareVersions(newBuild, build) <= 0 {
            fail(1, "new build \(newBuild) is not above prior item \(short) (build \(build))")
        }
        if newShort == short { fail(1, "prior item already has shortVersionString \(short) (build \(build))") }
    }
    let insertAt = priorItems[0].range.lowerBound
    let out = String(prior[..<insertAt]) + newItemText + String(prior[insertAt...])
    do { try out.write(toFile: o["out"]!, atomically: true, encoding: .utf8) } catch { fail(2, "cannot write \(o["out"]!)") }
    print("appcast: \(priorItems.count) prior item(s) kept, new item \(newShort) (build \(newBuild)) first")

case "sigs":
    guard args.count == 4 else { fail(2, "usage: sigs <appcast> <out-file>") }
    let feed = readText(args[2])
    var lines = ""
    for item in items(in: feed, name: args[2]) {
        let fields = stripCDATA(item.text)
        let row = [element("sparkle:version", in: fields), element("sparkle:shortVersionString", in: fields),
                   enclosureAttribute("url", in: fields), enclosureAttribute("length", in: fields),
                   enclosureAttribute("sparkle:edSignature", in: fields)]
        let values = row.compactMap { $0 }
        if values.count != 5 { fail(2, "an item lacks a version, url, length or signature") }
        if values.contains(where: { $0.rangeOfCharacter(from: .controlCharacters) != nil || $0.isEmpty }) {
            fail(2, "an item field is empty or holds a control character")
        }
        lines += values.joined(separator: "\t") + "\n"
    }
    let fm = FileManager.default
    if !fm.createFile(atPath: args[3], contents: lines.data(using: .utf8), attributes: [.posixPermissions: 0o600]) {
        fail(2, "cannot write \(args[3])")
    }

default:
    fail(2, "unknown subcommand \(args[1])")
}
