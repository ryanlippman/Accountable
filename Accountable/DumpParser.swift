import Foundation
import NaturalLanguage
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One thing pulled out of a brain dump, ready to review.
struct DumpItem: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var step: String
    var habit = false
    var when: Date? = nil
    var due: Date? = nil
    var include = true
}

/// Turns rambling speech into separate tasks, each with a tiny first step.
///
/// On iPhones with Apple Intelligence it uses Apple's on-device language model, which copes with
/// tangents, corrections ("no wait, Thursday") and run-on sentences. Everywhere else it uses a
/// rule-based splitter tuned for how people actually talk. Nothing leaves the phone either way.
enum DumpParser {
    static var usesModel: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SmartSplitter.isAvailable }
        #endif
        return false
    }

    static func parse(_ raw: String) async -> [DumpItem] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SmartSplitter.isAvailable, let items = await SmartSplitter.split(text), !items.isEmpty {
            return dedupe(items)
        }
        #endif
        let items = heuristic(text)
        if items.isEmpty {
            // Never lose what was said: keep it as one task.
            let t = tidy(text)
            return t.isEmpty ? [] : [DumpItem(title: String(t.prefix(80)), step: AppStore.tinyStep(for: t))]
        }
        return dedupe(items)
    }

    // MARK: Photos, screenshots and scans

    /// Text read off a page: assignment sheets, syllabi, whiteboards, screenshots of a to-do list or a chat.
    static func parseDocument(_ raw: String) async -> [DumpItem] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SmartSplitter.isAvailable, let items = await SmartSplitter.splitDocument(text), !items.isEmpty {
            return dedupe(items)
        }
        #endif
        return dedupe(documentLines(text))
    }

    private static let bullet = #"^\s*(?:[-•*·▪◦‣–—>]|\(?\d{1,2}[.)]|\(?[a-zA-Z][.)]|\[[ xX]?\]|☐|☑|✓|✔)\s*"#
    private static let noise = #"(?i)^(?:name|date|period|class|teacher|page|pg|due date|score|grade|points?)\s*[:#]?\s*\S{0,12}$|^\d{1,3}$|^https?://|^www\.|^[^a-zA-Z]*$"#
    private static let dueWords = #"(?i)\b(?:due|by|before|deadline|turn(?:ed)? in|submit(?:ted)? by)\b\s*:?\s*"#

    /// One task per line. A line that's only a date ("Monday 10/27") sets the due date for the lines under it.
    static func documentLines(_ text: String) -> [DumpItem] {
        var merged: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let isBullet = line.range(of: bullet, options: .regularExpression) != nil
            // A wrapped line starts lowercase and isn't a bullet: glue it to the line above.
            if let first = line.first, first.isLowercase, !isBullet, let last = merged.last, !last.hasSuffix(".") {
                merged[merged.count - 1] = last + " " + line
            } else {
                merged.append(line)
            }
        }

        var items: [DumpItem] = []
        var sectionDue: Date? = nil
        for var line in merged {
            line = line.replacingOccurrences(of: bullet, with: "", options: .regularExpression)
            if line.range(of: noise, options: .regularExpression) != nil { continue }
            var due: Date? = nil
            if let found = findDate(in: line) {
                let rest = tidy(found.remaining.replacingOccurrences(of: dueWords, with: " ", options: .regularExpression))
                // A heading that's just a day or date.
                if rest.split(separator: " ").count <= 1 {
                    sectionDue = found.date
                    continue
                }
                due = found.date
                line = found.remaining
            }
            line = line.replacingOccurrences(of: dueWords + "$", with: "", options: .regularExpression)
            let t = tidy(line.replacingOccurrences(of: leadIn, with: "", options: .regularExpression))
            guard t.count >= 3, !junk.contains(t.lowercased()) else { continue }
            let title = String(t.prefix(90))
            items.append(DumpItem(title: title, step: AppStore.tinyStep(for: title), due: due ?? sectionDue))
        }
        // Prose with few line breaks (a paragraph screenshot): fall back to the speech splitter.
        if items.count <= 1 && text.count > 120 { return heuristic(text) }
        return items
    }

    // MARK: Rule-based splitter

    private static let fillerPattern = #"\b(u+m+|u+h+|e+r+m*|hmm+|mm+)\b[,.]?"#
    private static let softFillers = [", like,", " you know,", " you know", " i guess", " basically", " kind of", " sort of",
                                      " and stuff", " or something", " or whatever", " literally", " honestly", " like, "]

    /// Where one thing ends and the next begins, in speech.
    private static let splitPattern = #"(?i)(?:;|\.\s|\?\s|!\s|\b(?:and then|and also|oh and|oh,? also|plus|after that|also|another thing(?: is)?|on top of that|besides that|then|firstly|secondly|thirdly|first of all|second|third|next|finally|lastly|and i (?:also )?(?:need|have|gotta|got|should|want|must|wanna)|i also (?:need|have|want|gotta|should))\b|,\s*(?:and\s+)?(?=(?:i\s+(?:need|have|gotta|should|want|must)|need to|have to|gotta|remember|don'?t forget|go|get|call|text|email|reply|finish|start|clean|do|buy|study|read|write|make|pick|send|pay|book|fix|wash|practice|review|submit|print|cancel|schedule|ask|tell|order|return|grab|take|bring|work on|look up|check)\b))"#

    private static let leadIn = #"(?i)^(?:(?:so|and|but|oh|well|ok(?:ay)?|right|um|also|yeah|then|alright)[\s,]+)*(?:(?:i\s+(?:really\s+|also\s+|definitely\s+|still\s+|probably\s+)?(?:need|have|gotta|got|should|want|must|wanna|'ve got|have got|need to remember|have to remember|should probably|ought)\s+(?:to\s+)?)|(?:i'?m\s+(?:going|gonna|supposed)\s+(?:to\s+)?)|(?:i\s+(?:think|guess)\s+i\s+(?:need|should|have)\s+(?:to\s+)?)|(?:remember\s+to\s+)|(?:don'?t\s+forget\s+(?:to\s+)?)|(?:gotta\s+|gonna\s+|need\s+to\s+|have\s+to\s+|want\s+to\s+|should\s+|maybe\s+|probably\s+|let'?s\s+|let\s+me\s+))*"#

    private static let junk: Set<String> = ["that's it", "thats it", "yeah", "okay", "ok", "so", "and", "i don't know", "idk", "what else",
                                            "let me think", "hmm", "that's all", "thats all", "nothing", "um", "uh", "anyway",
                                            "i think", "and stuff", "stuff", "things", "wait", "oh", "yes", "no"]

    private static let corrections = #"(?i)^(?:no\s+wait|wait\s+no|actually|i\s+mean|sorry|correction|no\s+no)[\s,]+"#
    private static let cancels = #"(?i)^(?:scratch\s+that|never\s*mind|forget\s+that|ignore\s+that|delete\s+that)\b"#
    private static let routine = #"(?i)\b(?:every\s+(?:single\s+)?(?:day|morning|night|evening|weekday|afternoon)|each\s+(?:day|morning|night|evening)|daily|nightly|every\s+day)\b"#

    static func heuristic(_ raw: String) -> [DumpItem] {
        var text = " " + raw + " "
        text = text.replacingOccurrences(of: fillerPattern, with: " ", options: [.regularExpression, .caseInsensitive])
        for f in softFillers { text = text.replacingOccurrences(of: f, with: " ", options: .caseInsensitive) }

        var pieces: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { r, _ in
            pieces += split(String(text[r]))
            return true
        }
        if pieces.isEmpty { pieces = split(text) }

        var items: [DumpItem] = []
        for var p in pieces {
            p = p.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if p.isEmpty { continue }
            if p.range(of: cancels, options: .regularExpression) != nil {
                if !items.isEmpty { items.removeLast() }
                continue
            }
            var replacing = false
            if let r = p.range(of: corrections, options: .regularExpression) {
                p.removeSubrange(r)
                replacing = true
            }
            guard var item = makeItem(p) else { continue }
            if replacing, let last = items.last {
                // "No wait, Thursday": a correction that's only a time fixes the time of the last thing.
                if item.title.split(separator: " ").count <= 2, item.when != nil {
                    items[items.count - 1].when = item.when
                    continue
                }
                if similarity(last.title, item.title) > 0.3 || item.title.split(separator: " ").count <= 3 {
                    item.habit = item.habit || last.habit
                    items[items.count - 1] = item
                    continue
                }
            }
            items.append(item)
        }
        return items
    }

    private static func split(_ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: splitPattern) else { return [s] }
        let ns = s as NSString
        var out: [String] = []
        var last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        out.append(ns.substring(from: last))
        return out
    }

    private static func makeItem(_ piece: String) -> DumpItem? {
        var p = piece
        var habit = false
        if let r = p.range(of: routine, options: .regularExpression) {
            habit = true
            p.removeSubrange(r)
        }
        var when: Date? = nil
        if let found = findDate(in: p) {
            when = found.date
            p = found.remaining
        }
        p = p.replacingOccurrences(of: leadIn, with: "", options: .regularExpression)
        let t = tidy(p)
        guard !t.isEmpty, !junk.contains(t.lowercased()) else {
            return nil
        }
        let words = t.split(separator: " ")
        if words.count == 1 && t.count < 4 { return nil }
        let title = String(t.prefix(80))
        return DumpItem(title: title, step: AppStore.tinyStep(for: title), habit: habit, when: when)
    }

    /// Finds a spoken time ("at 4", "tomorrow", "tonight") and removes it from the text.
    static func findDate(in s: String) -> (date: Date, remaining: String)? {
        var text = s
        var date: Date?
        let lower = text.lowercased()
        let cal = Calendar.current
        if lower.contains("tonight") {
            date = cal.date(bySettingHour: 20, minute: 0, second: 0, of: Date())
            text = text.replacingOccurrences(of: "tonight", with: "", options: .caseInsensitive)
        }
        if let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let ns = text as NSString
            if let m = det.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), let d = m.date {
                date = d
                var range = m.range
                // Take the little word before it too ("at", "on", "by").
                let before = ns.substring(to: range.location)
                if let r = before.range(of: #"(?i)\b(at|on|by|before|around|for|this|next)\s*$"#, options: .regularExpression) {
                    let start = before.distance(from: before.startIndex, to: r.lowerBound)
                    range = NSRange(location: start, length: range.location + range.length - start)
                }
                text = ns.replacingCharacters(in: range, with: " ")
            }
        }
        guard var d = date else { return nil }
        // A time with no day that's already passed means tomorrow.
        if d < Date().addingTimeInterval(-60), cal.isDateInToday(d) { d = cal.date(byAdding: .day, value: 1, to: d) ?? d }
        if d < Date().addingTimeInterval(-3600) { return nil }   // a past date is just part of the sentence
        return (d, text)
    }

    static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:!?-–—\"'")))
        t = t.replacingOccurrences(of: #"(?i)^(?:to|and|the|a|uh|so)\s+"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)\s+(?:and|or|but|so|too|as well|then)$"#, with: "", options: .regularExpression)
        guard let first = t.first else { return "" }
        return first.uppercased() + t.dropFirst()
    }

    // MARK: Cleanup

    static func dedupe(_ items: [DumpItem]) -> [DumpItem] {
        var out: [DumpItem] = []
        for i in items {
            if let j = out.firstIndex(where: { similarity($0.title, i.title) > 0.8 }) {
                if out[j].when == nil { out[j].when = i.when }
                out[j].habit = out[j].habit || i.habit
            } else {
                out.append(i)
            }
        }
        return out
    }

    /// Word overlap between two titles, 0...1.
    static func similarity(_ a: String, _ b: String) -> Double {
        let wa = Set(a.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let wb = Set(b.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        guard !wa.isEmpty, !wb.isEmpty else { return 0 }
        return Double(wa.intersection(wb).count) / Double(wa.union(wb).count)
    }
}

// MARK: - On-device model

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedDump {
    @Guide(description: "Every separate thing the speaker needs or wants to do, in the order they said them. One entry per thing.")
    var items: [GeneratedDumpItem]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedDumpItem {
    @Guide(description: "Short task title in plain words, starting with a verb, at most 8 words. Keep the speaker's own names, subjects and details.")
    var title: String
    @Guide(description: "One tiny, concrete first action for this task that takes under two minutes and needs no decisions, like 'Open the doc and write one sentence'.")
    var firstStep: String
    @Guide(description: "True only if the speaker wants to do this regularly, like every day or every morning.")
    var isRoutine: Bool
    @Guide(description: "When the speaker said they'd do it, copied word for word, like 'tomorrow at 4' or 'tonight'. Empty if they didn't say a time.")
    var when: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedDocItem {
    @Guide(description: "Short task title starting with a verb, at most 8 words, keeping names, page numbers and assignment titles.")
    var title: String
    @Guide(description: "One tiny, concrete first action that takes under two minutes.")
    var firstStep: String
    @Guide(description: "The due date or time exactly as written on the page, like 'Fri 10/31' or 'Nov 3 at 11:59pm'. Empty if none.")
    var due: String
}

@available(iOS 26.0, *)
@Generable
struct GeneratedDoc {
    @Guide(description: "Every assignment, task or to-do on the page, in order. Skip headings, names, instructions that aren't tasks, and anything already crossed off or checked.")
    var items: [GeneratedDocItem]
}

@available(iOS 26.0, *)
enum SmartSplitter {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static let instructions = """
    You turn a messy spoken brain dump into a clean to-do list for someone with ADHD.
    The text is a raw speech transcript: it rambles, repeats itself, has filler words, missing punctuation and run-on sentences.
    Find every separate thing the speaker needs or wants to do, including small errands, worries that imply an action, and things mentioned in passing.
    Split combined requests into separate items ("email Sam and finish the slides" is two items).
    If the speaker corrects themselves ("no wait", "actually", "I mean"), keep only the corrected version.
    If they cancel something ("scratch that", "never mind"), leave it out.
    Leave out filler, feelings with no action, and chatter. Never invent tasks they didn't mention.
    Write each first step as a physical action small enough to start in under two minutes.
    """

    static func split(_ text: String) async -> [DumpItem]? {
        var out: [DumpItem] = []
        for chunk in chunks(text, maxWords: 450) {
            let session = LanguageModelSession(instructions: instructions)
            do {
                let response = try await session.respond(to: "Brain dump transcript:\n\(chunk)", generating: GeneratedDump.self)
                for g in response.content.items {
                    let title = DumpParser.tidy(g.title)
                    guard !title.isEmpty else { continue }
                    var step = DumpParser.tidy(g.firstStep)
                    if step.isEmpty { step = AppStore.tinyStep(for: title) }
                    let when = g.when.trimmingCharacters(in: .whitespaces).isEmpty ? nil : DumpParser.findDate(in: g.when)?.date
                    out.append(DumpItem(title: String(title.prefix(80)), step: String(step.prefix(120)), habit: g.isRoutine, when: when))
                }
            } catch {
                // Guardrails or context limits: fall back to the rules for this chunk so nothing is lost.
                out += DumpParser.heuristic(chunk)
            }
        }
        return out
    }

    static func splitDocument(_ text: String) async -> [DumpItem]? {
        let session = LanguageModelSession(instructions: """
        You read text captured from a photo or screenshot (an assignment sheet, syllabus, whiteboard, planner page, to-do list or chat) and list what the person needs to do.
        The text comes from OCR, so it may have broken lines, odd spacing and typos. Fix obvious OCR mistakes in titles.
        If a date appears as a heading, it is the due date for the items under it.
        Never invent tasks that aren't on the page.
        """)
        do {
            let clipped = String(text.prefix(6000))
            let r = try await session.respond(to: "Captured text:\n\(clipped)", generating: GeneratedDoc.self)
            let items: [DumpItem] = r.content.items.compactMap { g in
                let title = DumpParser.tidy(g.title)
                guard !title.isEmpty else { return nil }
                let step = DumpParser.tidy(g.firstStep)
                let due = g.due.trimmingCharacters(in: .whitespaces).isEmpty ? nil : DumpParser.findDate(in: g.due)?.date
                return DumpItem(title: String(title.prefix(90)), step: step.isEmpty ? AppStore.tinyStep(for: title) : step, due: due)
            }
            return items
        } catch {
            return nil
        }
    }

    /// Splits long dumps at sentence boundaries so each piece fits the model's context.
    private static func chunks(_ text: String, maxWords: Int) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        var current = ""
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { r, _ in
            let sentence = String(text[r])
            let words = sentence.split(separator: " ").count
            if count + words > maxWords && !current.isEmpty {
                result.append(current)
                current = ""
                count = 0
            }
            current += sentence
            count += words
            return true
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { result.append(current) }
        if result.isEmpty { result = [text] }
        return result
    }
}
#endif
