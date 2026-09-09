import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Equatable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    // The four standard CGEvent modifier flag bits. Ignore Caps Lock, Fn and
    // numeric-pad flags: macOS also attaches those to ordinary function/arrow keys.
    public static let shift = Self(rawValue: 1 << 17)
    public static let control = Self(rawValue: 1 << 18)
    public static let option = Self(rawValue: 1 << 19)
    public static let command = Self(rawValue: 1 << 20)
    public static let supported: Self = [.shift, .control, .option, .command]
    public static func fromEventFlags(_ flags: UInt64) -> Self {
        Self(rawValue: flags).intersection(.supported)
    }
}

public struct Shortcut: Codable, Equatable {
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers
    public init(keyCode: UInt16, modifiers: ShortcutModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
    public var label: String { KeyCatalog.key(keyCode)?.name ?? "Unknown key" }
    public var isSupported: Bool { modifiers.isEmpty && KeyCatalog.key(keyCode) != nil }
}

public struct ZoomShortcuts: Codable, Equatable {
    public var zoomIn: Shortcut
    public var zoomOut: Shortcut
    public init(zoomIn: Shortcut = Shortcut(keyCode: 79), zoomOut: Shortcut = Shortcut(keyCode: 80)) {
        self.zoomIn = zoomIn
        self.zoomOut = zoomOut
    }
    public var isValid: Bool { zoomIn.isSupported && zoomOut.isSupported && zoomIn != zoomOut }
    public static func restored(from data: Data?) -> Self {
        guard let data, let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else {
            return Self()
        }
        return value
    }
}

public struct KeyDefinition: Identifiable {
    public let id: UInt16
    public let name: String
    public let group: String
    public let aliases: String
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || "\(name) \(aliases)".localizedCaseInsensitiveContains(query)
    }
}

/// Physical macOS keys, using the Carbon Events.h virtual key code table.
/// ANSI labels describe positions; they are not layout-dependent typed characters.
/// Media, power and modifier-only keys are deliberately outside this catalog.
public enum KeyCatalog {
    public static let groups = ["Function keys", "Letters & numbers", "Punctuation", "Navigation & editing", "Numeric keypad"]
    public static let all: [KeyDefinition] = {
        var result: [KeyDefinition] = []
        func add(_ group: String, _ entries: [(UInt16, String, String)]) {
            result += entries.map { KeyDefinition(id: $0.0, name: $0.1, group: group, aliases: $0.2) }
        }
        let functionCodes: [UInt16] = [122,120,99,118,96,97,98,100,101,109,103,111,105,107,113,106,64,79,80,90]
        add(groups[0], functionCodes.enumerated().map { ($0.element, "F\($0.offset + 1)", "") })
        add(groups[1], [(0,"A",""),(11,"B",""),(8,"C",""),(2,"D",""),(14,"E",""),(3,"F",""),(5,"G",""),(4,"H",""),(34,"I",""),(38,"J",""),(40,"K",""),(37,"L",""),(46,"M",""),(45,"N",""),(31,"O",""),(35,"P",""),(12,"Q",""),(15,"R",""),(1,"S",""),(17,"T",""),(32,"U",""),(9,"V",""),(13,"W",""),(7,"X",""),(16,"Y",""),(6,"Z",""),(29,"0",""),(18,"1",""),(19,"2",""),(20,"3",""),(21,"4",""),(23,"5",""),(22,"6",""),(26,"7",""),(28,"8",""),(25,"9","")])
        add(groups[2], [(24,"=","equals"),(27,"-","minus hyphen"),(30,"]","right bracket"),(33,"[","left bracket"),(39,"'","quote apostrophe"),(41,";","semicolon"),(42,"\\","backslash"),(43,",","comma"),(44,"/","slash"),(47,".","period dot"),(50,"`","grave backtick")])
        add(groups[3], [(36,"Return","enter"),(48,"Tab",""),(49,"Space","spacebar"),(51,"Delete","backspace"),(53,"Escape","esc"),(114,"Help","insert"),(115,"Home",""),(116,"Page Up","pageup pgup"),(117,"Forward Delete","del"),(119,"End",""),(121,"Page Down","pagedown pgdn"),(123,"Left Arrow","left"),(124,"Right Arrow","right"),(125,"Down Arrow","down"),(126,"Up Arrow","up")])
        add(groups[4], [(65,"Keypad .","decimal"),(67,"Keypad *","multiply"),(69,"Keypad +","plus"),(71,"Keypad Clear",""),(75,"Keypad /","divide"),(76,"Keypad Enter","return"),(78,"Keypad -","minus"),(81,"Keypad =","equals"),(82,"Keypad 0",""),(83,"Keypad 1",""),(84,"Keypad 2",""),(85,"Keypad 3",""),(86,"Keypad 4",""),(87,"Keypad 5",""),(88,"Keypad 6",""),(89,"Keypad 7",""),(91,"Keypad 8",""),(92,"Keypad 9","")])
        return result
    }()
    public static func key(_ code: UInt16) -> KeyDefinition? { all.first { $0.id == code } }
}
