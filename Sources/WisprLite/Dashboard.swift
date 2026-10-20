import AppKit

/// What the dashboard needs from the app; keeps menu state and settings in one place.
protocol DashboardHost: AnyObject {
    var isCleanupOn: Bool { get }
    var isFloatingOn: Bool { get }
    var currentPosition: Overlay.Position { get }
    var hotkeyName: String { get }
    var isLaunchAtLoginOn: Bool { get }
    func setCleanup(_ on: Bool)
    func setFloating(_ on: Bool)
    func setLaunchAtLogin(_ on: Bool)
    func setPosition(_ pos: Overlay.Position)
    func changeHotkey()
    func openKeyDialog()
    func openVocabulary()
}

private enum Theme {
    static let teal = NSColor(srgbRed: 0.18, green: 0.48, blue: 0.45, alpha: 1)
    static let emptyCell = NSColor.labelColor.withAlphaComponent(0.07)
    static let levels: [CGFloat] = [0.28, 0.52, 0.76, 1.0]
}

private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor, rounded: Bool = false) -> NSTextField {
    let f = NSTextField(labelWithString: text)
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let d = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: d, size: size) ?? font }
    f.font = font
    f.textColor = color
    return f
}

private func caption(_ text: String) -> NSTextField {
    let f = label(text.uppercased(), size: 11, weight: .semibold, color: .secondaryLabelColor)
    f.attributedStringValue = NSAttributedString(string: f.stringValue, attributes: [
        .font: f.font as Any, .foregroundColor: NSColor.secondaryLabelColor, .kern: 0.8])
    return f
}

private func vstack(_ views: [NSView], spacing: CGFloat, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
    let s = NSStackView(views: views)
    s.orientation = .vertical
    s.alignment = alignment
    s.spacing = spacing
    return s
}

private func pin(_ child: NSView, in parent: NSView, insets: NSEdgeInsets = NSEdgeInsets()) {
    child.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(child)
    NSLayoutConstraint.activate([
        child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
        child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
        child.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
        child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom),
    ])
}

/// Rounded panel with a subtle border.
private final class Card: NSView {
    init(_ content: NSView, padding: CGFloat = 20) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        pin(content, in: self, insets: NSEdgeInsets(top: padding, left: padding, bottom: padding, right: padding))
    }
    required init?(coder: NSCoder) { fatalError() }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.09).cgColor
        }
    }
}

/// Small colored square used in the heatmap legend.
private final class Swatch: NSView {
    private let alpha: CGFloat?
    private let outlined: Bool
    init(alpha: CGFloat?, outlined: Bool = false) {
        self.alpha = alpha
        self.outlined = outlined
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 14).isActive = true
        heightAnchor.constraint(equalToConstant: 14).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
        (alpha.map { Theme.teal.withAlphaComponent($0) } ?? Theme.emptyCell).setFill()
        path.fill()
        if outlined { Theme.teal.setStroke(); path.lineWidth = 1.5; path.stroke() }
    }
}

/// GitHub-style grid: columns are weeks, rows are Sun...Sat, shade shows how many words that day.
private final class Heatmap: NSView {
    private let weeks = 26, cell: CGFloat = 20, gap: CGFloat = 4, left: CGFloat = 34, top: CGFloat = 18
    private let stats: Stats
    private let monthFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }()

    init(_ stats: Stats) {
        self.stats = stats
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // One tooltip rect per day; userData carries the day's offset from the grid start (+1, since 0 would be nil).
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        for col in 0..<weeks {
            for row in 0..<7 {
                let offset = col * 7 + row
                guard let day = date(offset: offset), day <= today else { continue }
                let rect = NSRect(x: left + CGFloat(col) * (cell + gap), y: top + CGFloat(row) * (cell + gap), width: cell, height: cell)
                addToolTip(rect, owner: self, userData: UnsafeMutableRawPointer(bitPattern: offset + 1))
            }
        }
    }

    private lazy var tipFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    /// First day of the grid (a Sunday, `weeks - 1` weeks before this week) plus `offset` days.
    private func date(offset: Int) -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayRow = cal.component(.weekday, from: today) - 1          // Sunday = 0
        guard let start = cal.date(byAdding: .day, value: -((weeks - 1) * 7 + todayRow), to: today) else { return nil }
        return cal.date(byAdding: .day, value: offset, to: start)
    }

    @objc func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let data, let day = date(offset: Int(bitPattern: data) - 1) else { return "" }
        let words = stats.wordsPerDay[day] ?? 0
        let when = tipFormat.string(from: day)
        return words == 0 ? "\(when): no dictation" : "\(when): \(words.formatted()) word\(words == 1 ? "" : "s") dictated"
    }
    required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: left + CGFloat(weeks) * (cell + gap), height: top + 7 * (cell + gap))
    }

    override func draw(_ dirtyRect: NSRect) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayRow = cal.component(.weekday, from: today) - 1          // Sunday = 0
        guard let start = cal.date(byAdding: .day, value: -((weeks - 1) * 7 + todayRow), to: today) else { return }
        let maxWords = max(stats.wordsPerDay.values.max() ?? 1, 1)
        let small = NSFont.systemFont(ofSize: 10)
        let attrs: [NSAttributedString.Key: Any] = [.font: small, .foregroundColor: NSColor.secondaryLabelColor]

        for (row, name) in ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].enumerated() where row % 2 == 1 {
            NSAttributedString(string: name, attributes: attrs)
                .draw(at: NSPoint(x: 0, y: top + CGFloat(row) * (cell + gap) + 4))
        }
        var lastMonth = -1
        for col in 0..<weeks {
            let x = left + CGFloat(col) * (cell + gap)
            if let first = cal.date(byAdding: .day, value: col * 7, to: start) {
                let m = cal.component(.month, from: first)
                if m != lastMonth {
                    NSAttributedString(string: monthFormat.string(from: first), attributes: attrs).draw(at: NSPoint(x: x, y: 0))
                    lastMonth = m
                }
            }
            for row in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: col * 7 + row, to: start), day <= today else { continue }
                let rect = NSRect(x: x, y: top + CGFloat(row) * (cell + gap), width: cell, height: cell)
                let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
                if let words = stats.wordsPerDay[day] {
                    let level = min(Int(Double(words) / Double(maxWords) * 4), 3)
                    Theme.teal.withAlphaComponent(Theme.levels[level]).setFill()
                } else {
                    Theme.emptyCell.setFill()
                }
                path.fill()
                if stats.streakDays.contains(day) {
                    Theme.teal.setStroke(); path.lineWidth = 1.5; path.stroke()
                }
            }
        }
    }
}

final class Dashboard: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    enum Tab: Int { case insights, history, settings }

    weak var host: DashboardHost?
    private var window: NSWindow?
    private var tabs: NSSegmentedControl!
    private var content: NSView!
    private var tab = Tab.insights

    private var sessions: [Session] = []          // newest first, only ones with text
    private var searchText = ""
    private var table: NSTableView?

    private let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f
    }()
    private let timeFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    // MARK: Window

    func show(_ tab: Tab) {
        if window == nil { buildWindow() }
        select(tab)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Called after a new dictation or a setting change so an open window never goes stale.
    func reload() {
        if window != nil { select(tab) }
    }

    private func buildWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 600),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "WisprLite"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        let root = NSView()
        tabs = NSSegmentedControl(labels: ["Insights", "History", "Settings"], trackingMode: .selectOne,
                                  target: self, action: #selector(tabChanged))
        tabs.segmentStyle = .texturedRounded
        tabs.translatesAutoresizingMaskIntoConstraints = false
        content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tabs)
        root.addSubview(content)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            tabs.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            tabs.widthAnchor.constraint(equalToConstant: 300),
            content.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        w.contentView = root
        window = w
    }

    func windowWillClose(_ notification: Notification) {
        // Drop everything so the idle app holds no UI or history in memory.
        window?.delegate = nil
        window = nil
        table = nil
        sessions = []
        content = nil
        tabs = nil
    }

    @objc private func tabChanged() {
        select(Tab(rawValue: tabs.selectedSegment) ?? .insights)
    }

    private func select(_ t: Tab) {
        tab = t
        tabs.selectedSegment = t.rawValue
        content.subviews.forEach { $0.removeFromSuperview() }
        table = nil
        let view: NSView
        switch t {
        case .insights: view = makeInsights()
        case .history: view = makeHistory()
        case .settings: view = makeSettings()
        }
        pin(view, in: content)
    }

    // MARK: Insights

    private func makeInsights() -> NSView {
        let stats = Stats(History.load())

        let wpmNote: String
        if stats.wpm > 0 {
            let ratio = Double(stats.wpm) / 40          // average typing speed is about 40 wpm
            wpmNote = String(format: "%.1f× faster than typing at 40 wpm", ratio)
        } else {
            wpmNote = "Dictate a few sentences to see your speed"
        }
        let wpm = statCard(value: stats.wpm > 0 ? "\(stats.wpm)" : "–", title: "Words per minute", note: wpmNote)

        let pages = Double(stats.totalWords) / 500
        let totalNote = stats.totalWords == 0 ? "Nothing dictated yet" :
            "\(stats.todayWords.formatted()) today · \(stats.weekWords.formatted()) this week · ≈ \(pages < 10 ? String(format: "%.1f", pages) : Int(pages).formatted()) pages"
        let total = statCard(value: stats.totalWords.formatted(), title: "Total words dictated", note: totalNote)

        let row = NSStackView(views: [wpm, total])
        row.distribution = .fillEqually
        row.spacing = 16

        let streakTitle = label("\(stats.currentStreak) day streak", size: 28, weight: .bold, rounded: true)
        let longest = caption("Longest streak | \(stats.longestStreak) day\(stats.longestStreak == 1 ? "" : "s")")
        let header = NSView()
        for v in [streakTitle, longest] { v.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(v) }
        NSLayoutConstraint.activate([
            streakTitle.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            streakTitle.topAnchor.constraint(equalTo: header.topAnchor),
            streakTitle.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            longest.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            longest.centerYAnchor.constraint(equalTo: streakTitle.centerYAnchor),
        ])

        let legend = NSStackView(views: [
            label("Less", size: 11, color: .secondaryLabelColor),
            Swatch(alpha: nil), Swatch(alpha: Theme.levels[0]), Swatch(alpha: Theme.levels[1]),
            Swatch(alpha: Theme.levels[2]), Swatch(alpha: Theme.levels[3]),
            label("More", size: 11, color: .secondaryLabelColor),
            label("      ", size: 11),
            Swatch(alpha: nil, outlined: true),
            label("Current streak", size: 11, color: .secondaryLabelColor),
        ])
        legend.spacing = 6

        let inner = vstack([header, Heatmap(stats), legend], spacing: 14)
        header.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        let streak = Card(inner)

        let root = vstack([row, streak], spacing: 16)
        row.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        streak.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        let holder = NSView()
        pin(root, in: holder, insets: NSEdgeInsets(top: 12, left: 24, bottom: 0, right: 24))
        return holder
    }

    private func statCard(value: String, title: String, note: String) -> NSView {
        let n = label(note, size: 12, color: .secondaryLabelColor)
        n.lineBreakMode = .byWordWrapping
        n.maximumNumberOfLines = 2
        let stack = vstack([label(value, size: 44, weight: .bold, rounded: true), caption(title), n], spacing: 6)
        stack.setCustomSpacing(14, after: stack.views[1])
        let card = Card(stack)
        card.heightAnchor.constraint(equalToConstant: 170).isActive = true
        return card
    }

    // MARK: History

    private func makeHistory() -> NSView {
        let all = History.load()
        sessions = all.filter { !$0.text.isEmpty }.reversed()
        let shown = filtered()

        let search = NSSearchField()
        search.placeholderString = "Search your dictations"
        search.stringValue = searchText
        search.target = self
        search.action = #selector(searchChanged(_:))
        search.sendsSearchStringImmediately = true

        let t = NSTableView()
        t.dataSource = self
        t.delegate = self
        t.rowHeight = 48
        t.usesAlternatingRowBackgroundColors = true
        t.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (id, title, width) in [("when", "When", 130.0), ("text", "Dictation", 330.0), ("words", "Words", 60.0), ("copy", "", 150.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            c.title = title
            c.width = width
            if id == "text" { c.resizingMask = .autoresizingMask }
            t.addTableColumn(c)
        }
        table = t
        let scroll = NSScrollView()
        scroll.documentView = t
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .lineBorder

        let empty = label(all.isEmpty ? "No dictations yet. Hold your hotkey and speak." :
                            sessions.isEmpty ? "Dictation text isn't being saved (see Settings)." : "No matches.",
                          size: 13, color: .secondaryLabelColor)
        scroll.isHidden = shown.isEmpty
        empty.isHidden = !shown.isEmpty

        let count = label("\(sessions.count) saved dictation\(sessions.count == 1 ? "" : "s")", size: 12, color: .secondaryLabelColor)

        let root = NSView()
        for v in [search, scroll, empty, count] { v.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(v) }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            search.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            scroll.bottomAnchor.constraint(equalTo: count.topAnchor, constant: -10),
            count.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 26),
            count.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            empty.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            empty.centerYAnchor.constraint(equalTo: root.centerYAnchor),
        ])
        return root
    }

    private func filtered() -> [Session] {
        searchText.isEmpty ? sessions : sessions.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        searchText = sender.stringValue
        table?.reloadData()
    }

    private func whenString(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today, " + timeFormat.string(from: d) }
        if cal.isDateInYesterday(d) { return "Yesterday, " + timeFormat.string(from: d) }
        return dateFormat.string(from: d)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered().count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let list = filtered()
        guard let id = tableColumn?.identifier.rawValue, row < list.count else { return nil }
        let s = list[row]
        if id == "copy" {
            let copy = NSButton(title: "Copy", target: self, action: #selector(copyRow(_:)))
            let delete = NSButton(title: "Delete", target: self, action: #selector(deleteRow(_:)))
            for b in [copy, delete] { b.bezelStyle = .rounded; b.controlSize = .small }
            delete.contentTintColor = .systemRed
            let buttons = NSStackView(views: [copy, delete])
            buttons.spacing = 6
            let cell = NSTableCellView()
            buttons.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(buttons)
            NSLayoutConstraint.activate([buttons.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                                         buttons.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
            return cell
        }
        let text: String
        switch id {
        case "when": text = whenString(s.date)
        case "words": text = "\(s.words)"
        default: text = s.text
        }
        let field = NSTextField(wrappingLabelWithString: text)
        field.maximumNumberOfLines = id == "text" ? 2 : 1
        field.lineBreakMode = .byTruncatingTail
        field.font = .systemFont(ofSize: id == "text" ? 13 : 12)
        field.textColor = id == "text" ? .labelColor : .secondaryLabelColor
        field.toolTip = id == "text" ? s.text : nil
        let cell = NSTableCellView()
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func copyRow(_ sender: NSButton) {
        guard let t = table else { return }
        let row = t.row(for: sender)
        let list = filtered()
        guard row >= 0, row < list.count else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(list[row].text, forType: .string)
        sender.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { sender.title = "Copy" }
    }

    @objc private func deleteRow(_ sender: NSButton) {
        guard let t = table else { return }
        let row = t.row(for: sender)
        let list = filtered()
        guard row >= 0, row < list.count else { return }
        History.delete(date: list[row].date)
        select(.history)     // reload from disk so the table and counts stay accurate
    }

    // MARK: Settings

    private func makeSettings() -> NSView {
        guard let host else { return NSView() }
        let hotkeyValue = label(host.hotkeyName, size: 13, color: .secondaryLabelColor)
        let positions = NSPopUpButton(frame: .zero, pullsDown: false)
        for p in Overlay.Position.allCases { positions.addItem(withTitle: p.title) }
        positions.selectItem(at: Overlay.Position.allCases.firstIndex(of: host.currentPosition) ?? 0)
        positions.target = self
        positions.action = #selector(positionPicked(_:))

        let general = group("General", [
            setting("Hotkey", "Hold to talk, double-tap to lock on", buttons: [hotkeyValue, button("Change…", #selector(changeHotkey))]),
            setting("AI cleanup", "Fix punctuation and remove filler words", control: toggle(host.isCleanupOn, #selector(cleanupToggled(_:)))),
            setting("Launch at login", "Start WisprLite when you log in", control: toggle(host.isLaunchAtLoginOn, #selector(launchToggled(_:)))),
        ])
        let pill = group("Floating pill", [
            setting("Floating icon", "Keep the idle pill on screen", control: toggle(host.isFloatingOn, #selector(floatingToggled(_:)))),
            setting("Icon position", nil, control: positions),
        ])
        let history = group("History", [
            setting("Save dictation text", "Off keeps only word counts for your stats", control: toggle(History.saveText, #selector(saveTextToggled(_:)))),
            setting("Clear history and stats", "Deletes \(History.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))", control: button("Clear…", #selector(clearHistory))),
        ])
        let setup = group("Setup", [
            setting("Groq API key", "Stored in your Keychain", control: button("Set…", #selector(setKey))),
            setting("Vocabulary", "Names and terms Whisper should spell correctly", control: button("Edit…", #selector(editVocab))),
        ])
        let root = vstack([general, pill, history, setup], spacing: 16)
        for g in root.views { g.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        let holder = NSView()
        pin(root, in: holder, insets: NSEdgeInsets(top: 12, left: 24, bottom: 0, right: 24))
        return holder
    }

    private func group(_ title: String, _ rows: [NSView]) -> NSView {
        var items: [NSView] = []
        for (i, r) in rows.enumerated() {
            if i > 0 {
                let line = NSBox(); line.boxType = .separator
                items.append(line)
            }
            items.append(r)
        }
        let inner = vstack(items, spacing: 10)
        for v in items { v.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true }
        let card = Card(inner, padding: 14)
        let outer = vstack([caption(title), card], spacing: 6)
        card.widthAnchor.constraint(equalTo: outer.widthAnchor).isActive = true
        return outer
    }

    private func setting(_ title: String, _ detail: String?, control: NSView) -> NSView {
        setting(title, detail, buttons: [control])
    }

    private func setting(_ title: String, _ detail: String?, buttons: [NSView]) -> NSView {
        var texts: [NSView] = [label(title, size: 13, weight: .medium)]
        if let detail { texts.append(label(detail, size: 11, color: .secondaryLabelColor)) }
        let left = vstack(texts, spacing: 2)
        let right = NSStackView(views: buttons)
        right.spacing = 10
        let row = NSStackView(views: [left, NSView(), right])
        row.distribution = .fill
        row.alignment = .centerY
        return row
    }

    private func toggle(_ on: Bool, _ action: Selector) -> NSSwitch {
        let s = NSSwitch()
        s.state = on ? .on : .off
        s.target = self
        s.action = action
        return s
    }

    private func button(_ title: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        return b
    }

    @objc private func cleanupToggled(_ s: NSSwitch) { host?.setCleanup(s.state == .on) }
    @objc private func launchToggled(_ s: NSSwitch) { host?.setLaunchAtLogin(s.state == .on) }
    @objc private func floatingToggled(_ s: NSSwitch) { host?.setFloating(s.state == .on) }
    @objc private func saveTextToggled(_ s: NSSwitch) { History.saveText = s.state == .on }
    @objc private func positionPicked(_ p: NSPopUpButton) {
        let all = Overlay.Position.allCases
        if p.indexOfSelectedItem < all.count { host?.setPosition(all[p.indexOfSelectedItem]) }
    }
    @objc private func changeHotkey() { host?.changeHotkey(); reload() }
    @objc private func setKey() { host?.openKeyDialog() }
    @objc private func editVocab() { host?.openVocabulary() }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear all history and stats?"
        alert.informativeText = "This deletes every saved dictation and resets your word count, speed and streak. It can't be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        History.clear()
        reload()
    }
}
