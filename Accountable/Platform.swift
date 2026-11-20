import SwiftUI

/// Small switches for things that only make sense on a phone or only on a Mac.
enum Platform {
    /// True when running as the Mac version (Mac Catalyst) or as the iPhone app on an Apple silicon Mac.
    static var isMac: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return ProcessInfo.processInfo.isiOSAppOnMac
        #endif
    }

    /// Flipping the phone face down, the proximity sensor and the document camera need a phone.
    static var hasPhoneSensors: Bool { !isMac }
}

extension View {
    /// On wide windows (iPad, Mac) the tab's content sits in a centered column over the app background.
    func centeredTab(_ width: CGFloat = 820) -> some View {
        ZStack {
            Palette.bg.ignoresSafeArea()
            readableColumn(width)
        }
    }

    /// Keeps content at a comfortable reading width on iPad and Mac windows, centered.
    func readableColumn(_ width: CGFloat = 760) -> some View {
        frame(maxWidth: width).frame(maxWidth: .infinity)
    }
}
