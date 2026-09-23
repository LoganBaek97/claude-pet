import Testing
@testable import ClaudePetCore

struct PixelSurfaceTests {
    @Test func clearSurface() {
        var s = PixelSurface(width: 4, height: 4)
        s.fillRect(x: 0, y: 0, w: 4, h: 4, r: 255, g: 0, b: 0, a: 255)
        #expect(s.hasVisiblePixels)
        s.clear()
        #expect(!s.hasVisiblePixels)
    }

    @Test func blitSpriteFrameSwizzlesRGBAtoBGRA() {
        // 2x1 RGBA frame: red pixel, green pixel
        let frame = SpriteFrame(width: 2, height: 1, pixels: [
            255, 0, 0, 255,   // red
            0, 255, 0, 128,   // green, half-alpha (premultiplied)
        ])
        var surface = PixelSurface(width: 2, height: 1)
        surface.blitSpriteFrame(frame, dstX: 0, dstY: 0, dstW: 2, dstH: 1)
        // red pixel -> BGRA: B=0, G=0, R=255, A=255
        #expect(surface.pixels[0] == 0)   // B
        #expect(surface.pixels[1] == 0)   // G
        #expect(surface.pixels[2] == 255) // R
        #expect(surface.pixels[3] == 255) // A
        // green pixel -> BGRA: B=0, G=255, R=0, A=128
        #expect(surface.pixels[4] == 0)   // B
        #expect(surface.pixels[5] == 255) // G (already premultiplied in source)
        #expect(surface.pixels[6] == 0)   // R
        #expect(surface.pixels[7] == 128) // A
    }

    @Test func blitSpriteFrameScalesUp() {
        let frame = SpriteFrame(width: 1, height: 1, pixels: [100, 200, 50, 255])
        var surface = PixelSurface(width: 2, height: 2)
        surface.blitSpriteFrame(frame, dstX: 0, dstY: 0, dstW: 2, dstH: 2)
        // 4 pixels all the same (nearest-neighbour)
        for py in 0..<2 {
            for px in 0..<2 {
                let a = surface.alpha(atX: px, y: py)
                #expect(a == 255)
            }
        }
    }

    @Test func fillRoundedRectHasVisiblePixels() {
        var s = PixelSurface(width: 20, height: 20)
        s.fillRoundedRect(x: 0, y: 0, w: 20, h: 20, radius: 4, r: 30, g: 30, b: 30, a: 0xE0)
        #expect(s.hasVisiblePixels)
        // center pixel should have alpha
        #expect(s.alpha(atX: 10, y: 10) > 0)
        // corner pixel outside radius should be transparent
        #expect(s.alpha(atX: 0, y: 0) == 0)
    }

    @Test func compositeOverBlends() {
        var dst = PixelSurface(width: 2, height: 1)
        // fill with opaque white in BGRA
        dst.fillRect(x: 0, y: 0, w: 2, h: 1, r: 255, g: 255, b: 255, a: 255)

        var src = PixelSurface(width: 1, height: 1)
        // half-transparent black: premultiplied BGRA = (0,0,0,128)
        src.fillRect(x: 0, y: 0, w: 1, h: 1, r: 0, g: 0, b: 0, a: 128)

        dst.compositeOver(src, dstX: 0, dstY: 0)
        // pixel 0: black over white at ~50% → mid-grey
        let b = dst.pixels[0], g = dst.pixels[1], r = dst.pixels[2], a = dst.pixels[3]
        #expect(a == 255) // fully opaque result
        #expect(r > 100 && r < 200) // should be roughly half (127)
        // pixel 1: untouched white
        #expect(dst.pixels[6] == 255) // R
        #expect(dst.pixels[7] == 255) // A
    }

    @Test func alphaAtOutOfBoundsReturnsZero() {
        let s = PixelSurface(width: 1, height: 1)
        #expect(s.alpha(atX: -1, y: 0) == 0)
        #expect(s.alpha(atX: 0, y: -1) == 0)
        #expect(s.alpha(atX: 1, y: 0) == 0)
        #expect(s.alpha(atX: 0, y: 1) == 0)
    }

    @Test func aggregateSingleBuildsCorrectly() {
        let s = SessionState(sessionId: "x", state: .waiting, cwd: "/tmp/x", ts: 100)
        let summary = SessionSummary(session: s, state: .waiting)
        let agg = Aggregate.single(summary)
        #expect(agg.state == .waiting)
        #expect(agg.waitingCount == 1)
        #expect(agg.liveSessionCount == 1)
        #expect(agg.sessions.count == 1)
    }

    @Test func aggregateSingleRunningHasZeroWaiting() {
        let s = SessionState(sessionId: "x", state: .running, cwd: "/tmp/x", ts: 100)
        let summary = SessionSummary(session: s, state: .running)
        let agg = Aggregate.single(summary)
        #expect(agg.waitingCount == 0)
    }
}
