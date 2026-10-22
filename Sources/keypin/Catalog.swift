import AppKit
import Carbon
import Foundation

struct Source {
    let ref: TISInputSource

    var id: String { string(kTISPropertyInputSourceID) }
    var name: String { string(kTISPropertyLocalizedName) }
    var selectable: Bool { bool(kTISPropertyInputSourceIsSelectCapable) }
    var enabled: Bool { bool(kTISPropertyInputSourceIsEnabled) }
    var category: String { string(kTISPropertyInputSourceCategory) }

    var icon: NSImage? {
        if let url = value(kTISPropertyIconImageURL) as? URL, url.isFileURL,
           let image = NSImage(contentsOf: url), image.isValid {
            return image
        }
        // Keyboard layouts such as ABC still expose only IconRef through TIS.
        // This is an opaque Icon Services pointer, not a Core Foundation object.
        guard let pointer = TISGetInputSourceProperty(ref, kTISPropertyIconRef) else { return nil }
        return NSImage(iconRef: OpaquePointer(pointer))
    }

    var isCJKV: Bool {
        guard let lang = languages.first else { return false }
        return lang == "ko" || lang == "ja" || lang == "vi" || lang.hasPrefix("zh")
    }

    private var languages: [String] {
        (value(kTISPropertyInputSourceLanguages) as? [String]) ?? []
    }

    private func string(_ key: CFString) -> String {
        value(key) as? String ?? ""
    }

    private func bool(_ key: CFString) -> Bool {
        value(key) as? Bool ?? false
    }

    private func value(_ key: CFString) -> Any? {
        guard let pointer = TISGetInputSourceProperty(ref, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}

struct InputChoice: Identifiable, Equatable {
    let id: String
    let name: String
}

enum Catalog {
    static func selectable() -> [Source] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        let keyboard = kTISCategoryKeyboardInputSource as String
        return list.map(Source.init).filter {
            $0.enabled && $0.selectable && $0.category == keyboard
        }
    }

    static func choices() -> [InputChoice] {
        selectable().map { InputChoice(id: $0.id, name: $0.name) }
    }

    static func current() -> Source {
        Source(ref: TISCopyCurrentKeyboardInputSource().takeRetainedValue())
    }

    static func icon(for id: String) -> NSImage? {
        find(id)?.icon
    }

    static func find(_ id: String) -> Source? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }
        return list.map(Source.init).first { $0.enabled && $0.selectable && $0.category == (kTISCategoryKeyboardInputSource as String) && $0.id == id }
    }
}
