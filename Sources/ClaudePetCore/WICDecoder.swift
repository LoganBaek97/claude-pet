#if os(Windows)
import Foundation
import WinSDK

/// Windows Imaging Component 로 PNG 등을 RGBA8 프리멀티플라이드 알파로 디코딩한다.
/// CLI 의 `claude-pet add` 검증에서도 쓸 수 있도록 ClaudePetCore 에 둔다.
public enum WICDecoder: SpriteDecoder {
    // MARK: - COM GUID

    // WinSDK 의 Swift 모듈이 이 GUID 상수를 가져오지 못할 수 있으므로 문서 값으로 직접 정의한다.

    /// CLSID_WICImagingFactory {CACAF262-9370-4615-A13B-9F5539DA4C0A}
    private static let clsidFactory = GUID(
        Data1: 0xCACAF262, Data2: 0x9370, Data3: 0x4615,
        Data4: (0xA1, 0x3B, 0x9F, 0x55, 0x39, 0xDA, 0x4C, 0x0A))

    /// IID_IWICImagingFactory {EC5EC8A9-C395-4314-9C77-54D7A935FF70}
    private static let iidFactory = GUID(
        Data1: 0xEC5EC8A9, Data2: 0xC395, Data3: 0x4314,
        Data4: (0x9C, 0x77, 0x54, 0xD7, 0xA9, 0x35, 0xFF, 0x70))

    /// GUID_WICPixelFormat32bppPBGRA {6FDDC324-4E03-4BFE-B185-3D77768DC910}
    private static let pixelFormatPBGRA = GUID(
        Data1: 0x6FDDC324, Data2: 0x4E03, Data3: 0x4BFE,
        Data4: (0xB1, 0x85, 0x3D, 0x77, 0x76, 0x8D, 0xC9, 0x10))

    /// GUID_WICPixelFormat32bppPRGBA {3CC4A650-A527-4D37-A916-3142C7EBEDBA}
    private static let pixelFormatPRGBA = GUID(
        Data1: 0x3CC4A650, Data2: 0xA527, Data3: 0x4D37,
        Data4: (0xA9, 0x16, 0x31, 0x42, 0xC7, 0xEB, 0xED, 0xBA))

    // MARK: - 경로 정규화

    /// corelibs URL.path 는 `C:/Users/…` (슬래시)로 올 수 있다. Win32 API 는 백슬래시를 기대하므로
    /// 바꿔 준다. 드라이브 앞의 `/` 가 있으면 벗긴다.
    private static func winPath(_ url: URL) -> String {
        var p = url.path.replacingOccurrences(of: "/", with: "\\")
        // `/C:\…` 형태 방지
        if p.count >= 3, p.hasPrefix("\\"), p[p.index(p.startIndex, offsetBy: 2)] == ":",
           p[p.index(after: p.startIndex)].isLetter {
            p.removeFirst()
        }
        return p
    }

    // MARK: - 초기화

    /// COM 은 스레드마다 초기화해야 한다. 이미 되어 있으면 S_FALSE 가 온다.
    private static func ensureCOM() {
        let hr = CoInitializeEx(nil, DWORD(COINIT_APARTMENTTHREADED.rawValue))
        // S_OK(0) 또는 S_FALSE(1, 이미 초기화됨) 모두 성공이다.
        _ = hr
    }

    // MARK: - 디코딩

    public static func decode(contentsOf url: URL) throws -> SpriteFrame {
        ensureCOM()

        // 팩토리 생성
        var factoryPtr: UnsafeMutableRawPointer?
        var clsid = clsidFactory
        var iid = iidFactory
        var hr = CoCreateInstance(&clsid, nil, DWORD(CLSCTX_INPROC_SERVER), &iid, &factoryPtr)
        guard hr >= 0, let factoryRaw = factoryPtr else { throw SpriteSheetError.cannotDecode }
        let factory = factoryRaw.assumingMemoryBound(to: IWICImagingFactory.self)
        defer { factory.pointee.lpVtbl.pointee.Release(factory) }

        // 디코더 생성
        let path = winPath(url)
        var decoder: UnsafeMutablePointer<IWICBitmapDecoder>?
        hr = path.withCString(encodedAs: UTF16.self) { pathPtr in
            factory.pointee.lpVtbl.pointee.CreateDecoderFromFilename(
                factory, pathPtr, nil, DWORD(GENERIC_READ),
                WICDecodeMetadataCacheOnDemand, &decoder)
        }
        guard hr >= 0, let decoder else { throw SpriteSheetError.cannotDecode }
        defer { decoder.pointee.lpVtbl.pointee.Release(decoder) }

        // 첫 프레임
        var frame: UnsafeMutablePointer<IWICBitmapFrameDecode>?
        hr = decoder.pointee.lpVtbl.pointee.GetFrame(decoder, 0, &frame)
        guard hr >= 0, let frame else { throw SpriteSheetError.cannotDecode }
        defer { frame.pointee.lpVtbl.pointee.Release(frame) }

        // 포맷 컨버터 생성
        var converter: UnsafeMutablePointer<IWICFormatConverter>?
        hr = factory.pointee.lpVtbl.pointee.CreateFormatConverter(factory, &converter)
        guard hr >= 0, let converter else { throw SpriteSheetError.cannotDecode }
        defer { converter.pointee.lpVtbl.pointee.Release(converter) }

        // PBGRA 로 변환 시도, 성공하면 나중에 BGRA->RGBA 로 교환한다.
        var targetFormat = pixelFormatPBGRA
        var needsSwizzle = true
        hr = converter.pointee.lpVtbl.pointee.Initialize(
            converter, frame, &targetFormat,
            WICBitmapDitherTypeNone, nil, 0,
            WICBitmapPaletteTypeCustom)
        if hr < 0 {
            // PRGBA 시도
            targetFormat = pixelFormatPRGBA
            needsSwizzle = false
            hr = converter.pointee.lpVtbl.pointee.Initialize(
                converter, frame, &targetFormat,
                WICBitmapDitherTypeNone, nil, 0,
                WICBitmapPaletteTypeCustom)
            guard hr >= 0 else { throw SpriteSheetError.cannotDecode }
        }

        // 크기
        var w: UINT = 0, h: UINT = 0
        hr = converter.pointee.lpVtbl.pointee.GetSize(converter, &w, &h)
        guard hr >= 0, w > 0, h > 0 else { throw SpriteSheetError.cannotDecode }

        let width = Int(w), height = Int(h)
        let stride = width * 4
        let bufferSize = stride * height
        var pixels = [UInt8](repeating: 0, count: bufferSize)

        hr = pixels.withUnsafeMutableBufferPointer { buf in
            converter.pointee.lpVtbl.pointee.CopyPixels(
                converter, nil, UINT(stride), UINT(bufferSize), buf.baseAddress!)
        }
        guard hr >= 0 else { throw SpriteSheetError.cannotDecode }

        // PBGRA -> RGBA (premultiplied): B,G,R,A -> R,G,B,A
        if needsSwizzle {
            for i in stride(from: 0, to: bufferSize, by: 4) {
                let b = pixels[i + 0]
                let r = pixels[i + 2]
                pixels[i + 0] = r
                pixels[i + 2] = b
            }
        }

        return SpriteFrame(width: width, height: height, pixels: pixels)
    }
}
#endif
