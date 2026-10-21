//
//  ButtonStyleTests.swift
//  GuitarTapTests
//
//  What a button the app draws looks like, by kind and state, against the shared case file `button-style.json` —
//  the label's role, the fill and any wash over it, the border, and the opacity the whole button is drawn at.
//  `AppButtonLook.of` is the rule `AppButtonStyle` draws by. The same cases the Python and web suites run.
//
// @parity test/button-style

import Foundation
import Testing
@testable import GuitarTap

private final class ButtonStyleTestsAnchor {}

@Suite("ButtonStyle")
struct ButtonStyleTests {

    nonisolated(unsafe) static let data: [String: Any] = {
        let url = Bundle(for: ButtonStyleTestsAnchor.self).url(forResource: "button-style", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    static func ids() -> [String] {
        (data["cases"] as! [[String: Any]]).map { $0["id"] as! String }
    }

    private static func role(_ name: Any?) -> Palette.Role? { (name as? String).flatMap(Palette.Role.init(rawValue:)) }
    private static func opacity(_ name: Any?) -> Palette.Opacity? {
        (name as? String).flatMap(Palette.Opacity.init(rawValue:))
    }

    @Test(arguments: ids())
    func look(_ id: String) throws {
        let row = (Self.data["cases"] as! [[String: Any]]).first { $0["id"] as! String == id }!
        let role = Self.role(row["role"]) ?? .accent
        let kind: AppButtonKind = switch row["kind"] as! String {
        case "tinted": .tinted(role)
        case "prominent": .prominent(role)
        default: .plain
        }
        let state: AppButtonState = switch row["state"] as! String {
        case "hover": .hover
        case "pressed": .pressed
        case "on": .on
        case "onHover": .onHover
        case "cannotAct": .cannotAct
        default: .rest
        }
        let look = try #require(AppButtonLook.of(kind, state))
        let fill = row["fill"] as! [Any?]
        let wash = row["wash"] as? [Any?]
        #expect(look.text == Self.role(row["text"]), "\(id) text")
        #expect(look.fill == Self.role(fill[0]), "\(id) fill")
        #expect(look.fillOpacity == Self.opacity(fill[1]), "\(id) fill opacity")
        #expect(look.washRole == Self.role(wash?[0]), "\(id) wash")
        #expect(look.washOpacity == Self.opacity(wash?[1]), "\(id) wash opacity")
        #expect(look.border == Self.role(row["border"]), "\(id) border")
        #expect(look.drawnAt == Self.opacity(row["drawnAt"]), "\(id) drawn at")
    }
}
