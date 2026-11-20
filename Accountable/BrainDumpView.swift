import SwiftUI
import UIKit
import PhotosUI

/// Hold the button and say everything on your mind. Let go and it becomes a list of tasks,
/// each with a tiny first step. Slide up (or just tap) to keep listening hands-free.
struct BrainDumpView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Stage: Equatable { case ready, listening, thinking, review }

    @State private var recorder = VoiceRecorder()
    @State private var stage: Stage = .ready
    @State private var items: [DumpItem] = []
    @State private var parsedCount = 0
    @State private var locked = false
    @State private var pressing = false
    @State private var pressStart = Date()
    @State private var lift: CGFloat = 0
    @State private var ignoreGesture = false
    @State private var typing = false
    @State private var typed = ""
    @State private var denied = false
    @State private var empty = false
    @State private var scanning = false
    @State private var pickingShots = false
    @State private var pickingPhotos = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var readingImage = false
    @FocusState private var typeFocus: Bool

    private let lockDistance: CGFloat = 90
    private var theme: TimerTheme { TimerTheme.find(store.data.theme) }

    var body: some View {
        ZStack {
            NightBackdrop(theme: theme, intensity: stage == .listening ? 1 : 0.55)
            VStack(spacing: 0) {
                topBar
                switch stage {
                case .ready, .listening:
                    listening.transition(.opacity)
                case .thinking, .review:
                    review.transition(.opacity)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .animation(.calm, value: stage)
        .onDisappear { recorder.cancel() }
        .task {
            if VoiceRecorder.wasDenied { denied = true }
            if store.dumpStart != .voice { try? await Task.sleep(nanoseconds: 450_000_000) }
            switch store.dumpStart {
            case .scan: if DocumentScanner.isAvailable { scanning = true }
            case .screenshots: pickingShots = true
            case .photos: pickingPhotos = true
            case .voice: break
            }
            store.dumpStart = .voice
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { images in
                scanning = false
                if !images.isEmpty { Task { await readImages(images) } }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $pickingShots, selection: $picked, maxSelectionCount: 10, matching: .screenshots)
        .background {
            Color.clear.photosPicker(isPresented: $pickingPhotos, selection: $picked, maxSelectionCount: 10, matching: .images)
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            picked = []
            Task { @MainActor in
                var images: [UIImage] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { images.append(img) }
                }
                await readImages(images)
            }
        }
    }

    private func openSystemSettings() {
        #if targetEnvironment(macCatalyst)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { UIApplication.shared.open(url) }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #endif
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button {
                recorder.cancel()
                dismiss()
            } label: {
                Image(systemName: "xmark").font(.headline).foregroundStyle(Palette.nightMuted)
                    .frame(width: 40, height: 40)
                    .background(Palette.nightChip, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .accessibilityLabel("Close")
            Spacer()
            Text("Brain dump").font(.headline).foregroundStyle(Palette.nightInk)
            Spacer()
            Button {
                withAnimation(.calm) { typing.toggle() }
                if typing { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { typeFocus = true } }
            } label: {
                Image(systemName: typing ? "mic.fill" : "keyboard").font(.headline).foregroundStyle(Palette.nightMuted)
                    .frame(width: 40, height: 40)
                    .background(Palette.nightChip, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle(scale: 0.88))
            .accessibilityLabel(typing ? "Talk instead" : "Type instead")
            .opacity(stage == .ready || stage == .review ? 1 : 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: Listening

    private var listening: some View {
        VStack(spacing: 0) {
            if typing {
                typeBox.padding(.top, 20)
                Spacer()
            } else {
                if stage == .ready { sourceRow.padding(.top, 14).transition(.opacity) }
                transcriptArea
                Waveform(levels: recorder.levels, active: stage == .listening, theme: theme)
                    .frame(height: 64)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                recordControl
                    .padding(.bottom, 20)
            }
        }
    }

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if recorder.transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(stage == .listening ? "Listening…" : "Say everything on your mind.")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(Palette.nightInk)
                                .contentTransition(.opacity)
                            Text(empty ? "Didn't catch anything that time. Hold the button and try again."
                                       : "Tasks, errands, worries, half-ideas. Ramble all you want. It gets sorted into small steps.")
                                .font(.body)
                                .foregroundStyle(empty ? Palette.tasks : Palette.nightMuted)
                            if denied {
                                Button("Allow the microphone in Settings") {
                                    openSystemSettings()
                                }
                                .buttonStyle(SoftButtonStyle(color: theme.c1, dark: true))
                                .padding(.top, 8)
                            }
                            if let p = recorder.problem {
                                Label(p, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.tasks)
                            }
                        }
                    } else {
                        (Text(recorder.committed).foregroundStyle(Palette.nightInk)
                         + Text(recorder.committed.isEmpty ? "" : " ")
                         + Text(recorder.partial).foregroundStyle(Palette.nightInk.opacity(0.55)))
                            .font(.system(size: 24, weight: .semibold))
                            .lineSpacing(4)
                            .animation(.easeOut(duration: 0.15), value: recorder.partial)
                    }
                    if !items.isEmpty {
                        Label("\(items.count) already sorted. Keep going.", systemImage: "checklist")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.nightMuted)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 28)
            }
            .scrollIndicators(.hidden)
            .onChange(of: recorder.transcript) { _, _ in
                withAnimation(.calm) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
    }

    private var recordControl: some View {
        let active = stage == .listening
        let level = recorder.levels.last ?? 0
        return VStack(spacing: 14) {
            // Lock track: slide up to keep listening hands-free.
            ZStack {
                Capsule()
                    .fill(Palette.nightChip)
                    .overlay(Capsule().stroke(Palette.nightLine, lineWidth: 1))
                    .frame(width: 44, height: 86)
                Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(lift < -lockDistance * 0.7 || locked ? theme.c1 : Palette.nightMuted)
                    .offset(y: -22)
                    .contentTransition(.symbolEffect(.replace))
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.nightMuted)
                    .offset(y: 10)
            }
            .opacity(active && pressing && !locked ? 1 : 0)
            .scaleEffect(active && pressing && !locked ? 1 : 0.8, anchor: .bottom)
            .animation(.calm, value: pressing)

            ZStack {
                // Halo that breathes with your voice.
                Circle()
                    .fill(theme.c2.opacity(0.28))
                    .frame(width: 96, height: 96)
                    .scaleEffect(active && !reduceMotion ? 1 + level * 0.9 : 1)
                    .opacity(active ? 1 : 0)
                    .animation(.spring(response: 0.18, dampingFraction: 0.8), value: level)
                Circle()
                    .fill(theme.gradient)
                    .frame(width: 96, height: 96)
                    .shadow(color: theme.c2.opacity(0.5), radius: active ? 26 : 14, y: 6)
                    .overlay {
                        Image(systemName: locked ? "stop.fill" : "mic.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .scaleEffect(pressing ? 1.1 : 1)
                    .offset(y: locked ? 0 : lift)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressing)
            }
            .contentShape(Circle())
            .gesture(holdGesture)
            .accessibilityElement()
            .accessibilityLabel(active ? "Stop and sort" : "Start listening")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if active { finish() } else { locked = true; begin() }
            }

            Text(hint)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.nightMuted)
                .contentTransition(.opacity)
                .animation(.calm, value: hint)
            if !items.isEmpty && !active {
                Button("Review \(items.count) item\(items.count == 1 ? "" : "s")") {
                    withAnimation(.calm) { stage = .review }
                }
                .buttonStyle(SoftButtonStyle(color: theme.c1, dark: true))
                .padding(.horizontal, 60)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var hint: String {
        if stage == .listening {
            if locked { return "Listening hands-free. Tap to finish." }
            return lift < -lockDistance * 0.5 ? "Let go to keep listening" : "Let go to sort it · slide up to lock"
        }
        return "Hold to talk · tap to talk hands-free"
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if !pressing {
                    pressing = true
                    pressStart = Date()
                    if stage == .listening {
                        // Already listening hands-free: this press finishes.
                        ignoreGesture = true
                        finish()
                        return
                    }
                    ignoreGesture = false
                    begin()
                }
                guard !ignoreGesture, !locked, stage == .listening else { return }
                let dy = v.translation.height
                lift = dy < 0 ? -Motion.rubberband(-dy, dimension: 220, constant: 0.7) : 0
                if lift < -lockDistance * 0.62 {
                    locked = true
                    Haptics.shared.play(.rigid)
                    withAnimation(.reward) { lift = 0 }
                }
            }
            .onEnded { v in
                pressing = false
                defer { withAnimation(Motion.handoff(velocity: v.velocity.height, distance: -lift, bounce: 0.2)) { lift = 0 } }
                if ignoreGesture { ignoreGesture = false; return }
                if locked { return }
                if stage != .listening || Date().timeIntervalSince(pressStart) < 0.35 {
                    // A quick tap means "listen until I tap again".
                    locked = true
                    Haptics.shared.play(.rigid)
                } else {
                    finish()
                }
            }
    }

    // MARK: Photos, screenshots and scans

    private var sourceRow: some View {
        HStack(spacing: 8) {
            if DocumentScanner.isAvailable {
                sourceChip("Scan", "doc.viewfinder") { scanning = true }
            }
            sourceChip("Screenshots", "rectangle.dashed.badge.record") { pickingShots = true }
            sourceChip("Photos", "photo.on.rectangle") { pickingPhotos = true }
        }
        .padding(.horizontal, 20)
    }

    private func sourceChip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.nightInk)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Palette.nightChip, in: Capsule())
                .overlay(Capsule().stroke(Palette.nightLine, lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.94))
    }

    @MainActor
    private func readImages(_ images: [UIImage]) async {
        guard !images.isEmpty else { return }
        readingImage = true
        withAnimation(.calm) { stage = .thinking }
        let text = await TextScanner.read(images)
        let found = await DumpParser.parseDocument(text)
        readingImage = false
        if found.isEmpty {
            empty = true
            withAnimation(.calm) { stage = items.isEmpty ? .ready : .review }
            Haptics.shared.play(.error)
            return
        }
        for (i, item) in found.enumerated() {
            try? await Task.sleep(nanoseconds: i == 0 ? 120_000_000 : 80_000_000)
            withAnimation(.reward) { items.append(item) }
            Haptics.shared.play(.tick)
        }
        Haptics.shared.play(.success)
        SoundFX.shared.play(.pop)
        withAnimation(.calm) { stage = .review }
    }

    // MARK: Typing fallback

    private var typeBox: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Type it all out").font(.system(size: 28, weight: .bold)).foregroundStyle(Palette.nightInk)
            TextField("Finish the essay, email Mr. Green, clean my room…", text: $typed, axis: .vertical)
                .lineLimit(5...12)
                .font(.title3)
                .foregroundStyle(Palette.nightInk)
                .padding(16)
                .background(Palette.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Palette.nightLine, lineWidth: 1))
                .focused($typeFocus)
            Button("Sort it") {
                let t = typed
                typed = ""
                typeFocus = false
                Task { await sort(t, fromSpeech: false) }
            }
            .buttonStyle(GlowButtonStyle(theme: theme, dark: true))
            .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 24)
    }

    // MARK: Review

    private var review: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stage == .thinking ? (readingImage ? "Reading the page…" : "Sorting your thoughts…") : "Here's what I found")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Palette.nightInk)
                            .contentTransition(.opacity)
                        Text(stage == .thinking ? (DumpParser.usesModel ? "Using on-device intelligence. Nothing leaves your phone." : "Pulling out every separate thing.")
                                                : "Edit anything, untick what you don't need.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.nightMuted)
                    }
                    .padding(.bottom, 6)
                    if stage == .thinking && items.isEmpty {
                        ForEach(0..<3, id: \.self) { i in ShimmerCard(delay: Double(i) * 0.15) }
                    }
                    ForEach($items) { $item in
                        DumpCard(item: $item, theme: theme) {
                            withAnimation(.calm) { items.removeAll { $0.id == item.id } }
                        }
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)

            if stage == .review {
                VStack(spacing: 8) {
                    let count = items.filter(\.include).count
                    Button {
                        save()
                    } label: {
                        Text(count == 0 ? "Nothing selected" : "Add \(count) item\(count == 1 ? "" : "s")")
                            .contentTransition(.numericText(value: Double(count)))
                    }
                    .buttonStyle(GlowButtonStyle(theme: theme, dark: true))
                    .disabled(count == 0)
                    Button {
                        withAnimation(.calm) { stage = .ready; typing = false }
                    } label: {
                        Label("Keep talking", systemImage: "mic.fill")
                    }
                    .buttonStyle(SoftButtonStyle(color: theme.c1, dark: true))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: Flow

    private func begin() {
        empty = false
        Task { @MainActor in
            if !VoiceRecorder.hasPermission {
                let ok = await VoiceRecorder.requestPermission()
                if !ok {
                    denied = true
                    pressing = false
                    Haptics.shared.play(.error)
                    return
                }
                denied = false
                // The permission alert interrupted the press, so continue hands-free.
                locked = true
            }
            recorder.start()
            if recorder.state == .listening {
                Haptics.shared.play(.medium)
                withAnimation(.calm) { stage = .listening }
            } else {
                Haptics.shared.play(.error)
            }
        }
    }

    private func finish() {
        guard stage == .listening else { return }
        Haptics.shared.play(.light)
        locked = false
        Task { @MainActor in
            let text = await recorder.stop()
            let fresh = String(text.dropFirst(parsedCount))
            parsedCount = text.count
            await sort(fresh, fromSpeech: true)
        }
    }

    @MainActor
    private func sort(_ text: String, fromSpeech: Bool) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            empty = true
            withAnimation(.calm) { stage = items.isEmpty ? .ready : .review }
            return
        }
        withAnimation(.calm) { stage = .thinking }
        let found = await DumpParser.parse(text)
        for (i, item) in found.enumerated() {
            try? await Task.sleep(nanoseconds: i == 0 ? 120_000_000 : 90_000_000)
            withAnimation(.reward) { items.append(item) }
            Haptics.shared.play(.tick)
        }
        if found.isEmpty && items.isEmpty {
            empty = true
            withAnimation(.calm) { stage = .ready }
        } else {
            Haptics.shared.play(.success)
            SoundFX.shared.play(.pop)
            withAnimation(.calm) { stage = .review }
        }
    }

    private func save() {
        var tasks = 0, habits = 0
        for i in items where i.include {
            let title = i.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            if i.habit {
                store.addHabit(title)
                habits += 1
            } else if let id = store.addTask(title, firstStep: i.step) {
                if let w = i.when, w > Date() { store.planTask(id, at: w) }
                if let d = i.due { store.setDue(id, d) }
                tasks += 1
            }
        }
        if tasks + habits > 0 {
            store.bump("dumps")
            store.confetti += 1
            Haptics.shared.sparkle()
            SoundFX.shared.play(.quest)
        }
        recorder.cancel()
        dismiss()
    }
}

// MARK: - Pieces

private struct Waveform: View {
    let levels: [CGFloat]
    let active: Bool
    let theme: TimerTheme

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(active ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(Color.white.opacity(0.15)))
                    .frame(width: 3.5, height: max(4, levels[i] * 60))
                    .opacity(active ? 0.35 + Double(i) / Double(max(1, levels.count)) * 0.65 : 1)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.16, dampingFraction: 0.9), value: levels)
        .accessibilityHidden(true)
    }
}

private struct DumpCard: View {
    @Binding var item: DumpItem
    let theme: TimerTheme
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.reward) { item.include.toggle() }
                Haptics.shared.play(.light)
            } label: {
                Image(systemName: item.include ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.include ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(Palette.nightMuted))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle(haptic: .none, scale: 0.85))
            .accessibilityLabel(item.include ? "Included" : "Not included")

            VStack(alignment: .leading, spacing: 8) {
                TextField("Task", text: $item.title, axis: .vertical)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.include ? Palette.nightInk : Palette.nightMuted)
                    .lineLimit(1...3)
                if !item.habit {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "shoeprints.fill").font(.caption2).foregroundStyle(theme.c1)
                        TextField("First step", text: $item.step, axis: .vertical)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(theme.c1)
                            .lineLimit(1...2)
                    }
                }
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.calm) { item.habit.toggle() }
                        Haptics.shared.play(.tick)
                    } label: {
                        Label(item.habit ? "Daily habit" : "Task", systemImage: item.habit ? "repeat" : "checklist")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).frame(height: 26)
                            .background((item.habit ? Palette.habits : Color.white).opacity(item.habit ? 0.22 : 0.08), in: Capsule())
                            .foregroundStyle(item.habit ? Palette.habits : Palette.nightMuted)
                    }
                    .buttonStyle(PressableStyle(scale: 0.94))
                    if let d = item.due, !item.habit {
                        Button {
                            withAnimation(.calm) { item.due = nil }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text("Due " + d.formatted(Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()))
                                Image(systemName: "xmark").font(.system(size: 8, weight: .black))
                            }
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Palette.tasks.opacity(0.18), in: Capsule())
                            .foregroundStyle(Palette.tasks)
                        }
                        .buttonStyle(PressableStyle(scale: 0.94))
                    }
                    if let w = item.when, !item.habit {
                        Button {
                            withAnimation(.calm) { item.when = nil }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "alarm")
                                Text(Calendar.current.isDateInToday(w)
                                     ? w.formatted(date: .omitted, time: .shortened)
                                     : w.formatted(Date.FormatStyle().weekday(.abbreviated).hour().minute()))
                                Image(systemName: "xmark").font(.system(size: 8, weight: .black))
                            }
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Palette.shield.opacity(0.18), in: Capsule())
                            .foregroundStyle(Palette.shield)
                        }
                        .buttonStyle(PressableStyle(scale: 0.94))
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.nightMuted)
                    .frame(width: 28, height: 28)
                    .background(Palette.nightChip, in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.85))
            .accessibilityLabel("Remove")
        }
        .padding(14)
        .background(Palette.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(item.include ? theme.c1.opacity(0.35) : Palette.nightLine, lineWidth: 1))
        .opacity(item.include ? 1 : 0.6)
    }
}

private struct ShimmerCard: View {
    let delay: Double
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.10)).frame(height: 16).frame(maxWidth: 220)
            RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.06)).frame(height: 12).frame(maxWidth: 160)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.nightChip, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(on ? 1 : 0.45)
        .onAppear {
            guard !reduceMotion else { on = true; return }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true).delay(delay)) { on = true }
        }
        .transition(.opacity)
    }
}
