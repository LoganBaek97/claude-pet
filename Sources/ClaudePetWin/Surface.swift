#if os(Windows)
import ClaudePetCore
import Foundation
import WinSDK

/// PixelSurface 와 Win32 DIB 를 잇는 얇은 계층.
/// PixelSurface 가 합성을 하고 이쪽은 DIB 에 복사해 UpdateLayeredWindow 에 넘긴다.
enum Surface {
    /// 32bpp top-down BGRA DIB 를 만든다. 반환값의 bits 에 직접 쓸 수 있다.
    static func createDIB(width: Int32, height: Int32, screenDC: HDC?) -> (hBitmap: HBITMAP, bits: UnsafeMutablePointer<UInt8>)? {
        var bmi = BITMAPINFO()
        bmi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bmi.bmiHeader.biWidth = width
        bmi.bmiHeader.biHeight = -height  // top-down
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        bmi.bmiHeader.biCompression = DWORD(BI_RGB)
        var raw: UnsafeMutableRawPointer?
        guard let bmp = CreateDIBSection(screenDC, &bmi, UINT(DIB_RGB_COLORS), &raw, nil, 0),
              let bits = raw else { return nil }
        return (bmp, bits.assumingMemoryBound(to: UInt8.self))
    }

    /// PixelSurface 의 픽셀을 DIB bits 에 복사한다. 둘 다 BGRA top-down, 크기 같다고 가정한다.
    static func copy(_ surface: PixelSurface, to bits: UnsafeMutablePointer<UInt8>) {
        surface.pixels.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            bits.update(from: base, count: src.count)
        }
    }

    /// 스프라이트 프레임의 크기를 Preferences.scale 에 맞춘다.
    static func scaledSize(scale: Double) -> (w: Int, h: Int) {
        let w = Int(Double(SpriteSheet.cellWidth) * scale)
        let h = Int(Double(SpriteSheet.cellHeight) * scale)
        return (w, h)
    }
}
#endif
