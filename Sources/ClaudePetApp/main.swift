#if os(macOS)
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
#else
// macOS 전용 실행 파일. 다른 플랫폼에서는 빈 진입점만 남겨 패키지 전체 빌드를 막지 않는다.
#endif
