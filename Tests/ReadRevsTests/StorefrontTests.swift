import Foundation
import Testing
@testable import ReadRevs

@Suite("App Store storefront catalog")
struct StorefrontTests {
    @Test("Contains exactly Apple's 175 supported countries and regions")
    func hasCompleteUniqueCatalog() {
        let expectedCodes = Set(
            "ae af ag ai al am ao ar at au az ba bb be bf bg bh bj bm bn bo br bs bt bw by bz ca cd cg ch ci cl cm cn co cr cv cy cz de dk dm do dz ec ee eg es fi fj fm fr ga gb gd ge gh gm gr gt gw gy hk hn hr hu id ie il in iq is it jm jo jp ke kg kh kn kr kw ky kz la lb lc lk lr lt lu lv ly ma md me mg mk ml mm mn mo mr ms mt mu mv mw mx my mz na ne ng ni nl no np nr nz om pa pe pg ph pk pl pt pw py qa ro rs ru rw sa sb sc se sg si sk sl sn sr st sv sz tc td th tj tm tn to tr tt tw tz ua ug us uy uz vc ve vg vn vu xk ye za zm zw"
                .split(separator: " ")
                .map(String.init)
        )

        #expect(Storefront.allCases.count == 175)
        #expect(Set(Storefront.allCases.map(\.rawValue)).count == 175)
        #expect(Storefront.allCases.allSatisfy { $0.rawValue.count == 2 })
        #expect(Set(Storefront.allCases.map(\.rawValue)) == expectedCodes)
    }

    @Test("Preserves named storefront conveniences")
    func preservesNamedStorefronts() {
        #expect(Storefront.unitedStates.rawValue == "us")
        #expect(Storefront.unitedKingdom.rawValue == "gb")
        #expect(Storefront.czechia.rawValue == "cz")
        #expect(Storefront.japan.displayName == "Japan")
    }

    @Test("Codable remains compatible with the original single-string format")
    func preservesSingleStringCodableFormat() throws {
        let decoded = try JSONDecoder().decode(Storefront.self, from: Data(#""cz""#.utf8))
        let encoded = try JSONEncoder().encode(Storefront.unitedStates)

        #expect(decoded == .czechia)
        #expect(String(decoding: encoded, as: UTF8.self) == #""us""#)
    }

    @Test("Rejects codes outside the App Store catalog")
    func rejectsUnsupportedCode() {
        #expect(Storefront(rawValue: "xx") == nil)
        #expect(Storefront(rawValue: "US") == nil)
    }
}
