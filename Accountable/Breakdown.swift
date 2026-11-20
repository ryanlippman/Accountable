import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Splits a big task into 3 to 6 small, ordered steps.
enum TaskBreaker {
    static func breakDown(_ title: String) async -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SmartSplitter.isAvailable, let steps = await ModelBreaker.steps(for: title), steps.count >= 2 {
            return steps
        }
        #endif
        return template(for: title)
    }

    static func template(for title: String) -> [String] {
        let t = title.lowercased()
        let sets: [([String], [String])] = [
            (["essay", "paper", "report", "write", "draft", "article", "story", "paragraph"],
             ["Open a doc and write the title", "Jot down 3 points you want to make", "Write a rough first paragraph",
              "Draft the middle, one point at a time", "Write the ending", "Read it once and fix the obvious stuff"]),
            (["study", "test", "exam", "quiz", "midterm", "final", "review"],
             ["Gather your notes and the study guide", "List the topics that will be on it", "Review the first topic for 10 minutes",
              "Do a few practice questions", "Mark anything you're unsure about", "Go over just the marked parts"]),
            (["read", "chapter", "book", "pages"],
             ["Find the pages and grab a pen", "Skim the headings for 2 minutes", "Read the first section",
              "Write a one-line note per section", "Read the rest", "Write 3 takeaways"]),
            (["clean", "tidy", "room", "organize", "declutter"],
             ["Grab a bag for trash", "Throw out anything that's trash", "Put clothes in the hamper or drawers",
              "Clear the desk", "Clear the floor", "Make the bed"]),
            (["homework", "problem", "worksheet", "math", "assignment", "lab", "calc"],
             ["Open it and read the instructions", "Do the easiest problem first", "Do the next three",
              "Mark any you're stuck on", "Finish the rest", "Go back to the stuck ones"]),
            (["slides", "presentation", "deck", "speech", "debate"],
             ["Write the one main point", "List 4 to 6 slide titles", "Make the title slide",
              "Fill in one slide at a time", "Practice it out loud once", "Fix what felt awkward"]),
            (["code", "bug", "app", "feature", "project", "build", "game", "script"],
             ["Write down what done looks like", "Open the project", "List the next 3 changes",
              "Make the smallest change", "Test it", "Save or commit"]),
            (["apply", "application", "form", "college", "scholarship"],
             ["Open the form and fill in the basics", "List what documents you need", "Gather those documents",
              "Answer the short questions", "Draft the long answers", "Check everything and submit"]),
            (["email", "message", "reply", "text"],
             ["Open a new draft", "Write the one thing you need to say", "Add a greeting and sign-off", "Read it once and send"]),
            (["laundry", "dishes", "chores"],
             ["Put on a song", "Gather everything in one place", "Start the first load", "Put the clean stuff away"])
        ]
        for (keys, steps) in sets where keys.contains(where: { t.contains($0) }) { return steps }
        return ["Write down what done looks like", "Gather what you need", "Do the first 10 minutes",
                "Keep going to the halfway point", "Finish the last part", "Quick check, then mark it done"]
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedSteps {
    @Guide(description: "Between 3 and 6 small steps, in the order to do them. Each one short, concrete and doable in under 15 minutes.", .maximumCount(6))
    var steps: [String]
}

@available(iOS 26.0, *)
enum ModelBreaker {
    static func steps(for title: String) async -> [String]? {
        let session = LanguageModelSession(instructions: """
        You help someone with ADHD start big tasks by breaking them into small, concrete, ordered steps.
        Each step starts with a verb, is under 10 words, and is small enough to start right away.
        The first step should be almost effortless. Be specific to the task. Don't add commentary.
        """)
        do {
            let r = try await session.respond(to: "Task: \(title)", generating: GeneratedSteps.self)
            let steps = r.content.steps.map { DumpParser.tidy($0) }.filter { !$0.isEmpty }
            return Array(steps.prefix(6))
        } catch {
            return nil
        }
    }
}
#endif

// MARK: - Drawer

struct BreakdownDrawer: View {
    @Environment(AppStore.self) private var store
    @Environment(DrawerCenter.self) private var drawers
    let taskID: UUID

    @State private var editing = false
    @State private var drafts: [Draft] = []
    @State private var loading = false
    @State private var newStep = ""

    struct Draft: Identifiable, Equatable {
        let id = UUID()
        var text: String
    }

    private var task: WorkTask? { store.data.tasks.first { $0.id == taskID } }

    var body: some View {
        let t = task
        VStack(spacing: 12) {
            DrawerTitle(title: "Break it down", message: t?.title, icon: "list.bullet.indent", iconColor: Color(hex: 0x0D9488))
            if let t, !t.steps.isEmpty, !editing {
                checklist(t)
            } else {
                editor
            }
        }
        .onAppear {
            if let t, t.steps.isEmpty { generate() }
        }
        .animation(.calm, value: editing)
    }

    // Checking steps off

    private func checklist(_ t: WorkTask) -> some View {
        let done = t.steps.filter(\.done).count
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Bar(value: Double(done) / Double(max(1, t.steps.count)), color: Color(hex: 0x0D9488), height: 8)
                Text("\(done)/\(t.steps.count)")
                    .font(.caption.weight(.bold)).monospacedDigit().foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(done)))
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(t.steps) { s in
                        Button {
                            withAnimation(.reward) { store.toggleStep(t.id, s.id) }
                            if !s.done {
                                Haptics.shared.play(.success)
                                SoundFX.shared.play(.xp)
                            } else {
                                Haptics.shared.play(.light)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: s.done ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(s.done ? Color(hex: 0x0D9488) : Color.secondary)
                                    .contentTransition(.symbolEffect(.replace))
                                Text(s.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(s.done ? Color.secondary : Color.primary)
                                    .strikethrough(s.done, color: .secondary)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if !s.done && s.id == t.steps.first(where: { !$0.done })?.id {
                                    Text("NEXT").font(.caption2.weight(.heavy)).foregroundStyle(Palette.ember)
                                }
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 50)
                            .background(Palette.track, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(PressableStyle(haptic: .none, scale: 0.98))
                    }
                }
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            if done == t.steps.count {
                Button("All steps done · finish the task") {
                    drawers.dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.finishTask(t.id) }
                }
                .buttonStyle(GlowButtonStyle(tint: Palette.good))
            } else {
                Button {
                    drawers.dismiss()
                    store.sessionRequest = SessionConfig(taskID: t.id, minutes: store.data.defaultMinutes)
                } label: {
                    Label("Focus on the next step", systemImage: "play.fill")
                }
                .buttonStyle(GlowButtonStyle(theme: TimerTheme.find(store.data.theme)))
            }
            Button("Edit steps") {
                drafts = t.steps.map { Draft(text: $0.title) }
                editing = true
            }
            .buttonStyle(SoftButtonStyle(color: .secondary))
        }
    }

    // Writing / reviewing steps

    private var editor: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 8) {
                    if loading && drafts.isEmpty {
                        ForEach(0..<4, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Palette.track)
                                .frame(height: 50)
                                .opacity(0.5 + Double(3 - i) * 0.12)
                        }
                    }
                    ForEach($drafts) { $d in
                        HStack(spacing: 10) {
                            Text("\((drafts.firstIndex(of: d) ?? 0) + 1)")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color(hex: 0x0D9488), in: Circle())
                            TextField("Step", text: $d.text, axis: .vertical)
                                .font(.body.weight(.medium))
                                .lineLimit(1...2)
                            Button {
                                withAnimation(.calm) { drafts.removeAll { $0.id == d.id } }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.tertiary).font(.title3)
                            }
                            .buttonStyle(PressableStyle(scale: 0.85))
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 50)
                        .background(Palette.track, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if !loading {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Color(hex: 0x0D9488))
                            TextField("Add a step", text: $newStep)
                                .submitLabel(.done)
                                .onSubmit {
                                    let s = newStep.trimmingCharacters(in: .whitespaces)
                                    guard !s.isEmpty else { return }
                                    withAnimation(.calm) { drafts.append(Draft(text: s)) }
                                    newStep = ""
                                }
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 50)
                    }
                }
            }
            .frame(maxHeight: 340)
            .fixedSize(horizontal: false, vertical: true)
            Button(loading ? "Breaking it down…" : "Save steps") {
                store.setSteps(taskID, drafts.map(\.text))
                Haptics.shared.play(.success)
                SoundFX.shared.play(.pop)
                withAnimation(.calm) { editing = false }
            }
            .buttonStyle(GlowButtonStyle(tint: Color(hex: 0x0D9488)))
            .disabled(loading || drafts.allSatisfy { $0.text.trimmingCharacters(in: .whitespaces).isEmpty })
            Button {
                generate()
            } label: {
                Label("Suggest different steps", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(SoftButtonStyle(color: Color(hex: 0x0D9488)))
            .disabled(loading)
        }
    }

    private func generate() {
        guard let t = task else { return }
        loading = true
        withAnimation(.calm) { drafts = [] }
        Task { @MainActor in
            let steps = await TaskBreaker.breakDown(t.title)
            for (i, s) in steps.enumerated() {
                try? await Task.sleep(nanoseconds: i == 0 ? 100_000_000 : 80_000_000)
                withAnimation(.reward) { drafts.append(Draft(text: s)) }
                Haptics.shared.play(.tick)
            }
            loading = false
            editing = true
        }
    }
}
