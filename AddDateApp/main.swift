// AddDate.app — native window for add_date.py
//
// Shows the "Add Date to Image File Name" window (time and position switches,
// live preview of the new name, Cancel / Rename N file(s)), writes the choice
// as JSON to the --out file, then quits. Also posts the end-of-task
// notification (see "Notification mode"). Reading the dates and renaming stay
// in add_date.py.
//
// Arguments (all "--key value"):
//   --count <n>    number of files to rename (shown on the default button)
//   --after <1|0>  "Position the information after the file name" switch
//   --time <1|0>   "Add hours and minutes" switch
//   --out <path>   where to write {"cancelled":…, "after":…, "time":…}
//
// Build with build_app.sh (needs the Xcode Command Line Tools).

import AppKit
import SwiftUI
import UserNotifications

let WINDOW_TITLE = "Add Date to Image File Name"

// MARK: - Arguments

struct Args {
    var count = 0
    var after = false
    var time = true
    var out: URL?
}

func parseArgs() -> Args {
    var args = Args()
    var items = CommandLine.arguments.dropFirst().makeIterator()
    while let key = items.next() {
        guard key.hasPrefix("--"), let value = items.next() else { continue }
        switch key {
        case "--count": args.count = Int(value) ?? 0
        case "--after": args.after = (value == "1")
        case "--time": args.time = (value == "1")
        case "--out": args.out = URL(fileURLWithPath: value)
        default: break
        }
    }
    return args
}

// MARK: - Model

@MainActor
final class Model: ObservableObject {
    @Published var after: Bool
    @Published var time: Bool
    let count: Int

    init(args: Args) {
        count = args.count
        after = args.after
        time = args.time
    }

    var result: [String: Any] { ["after": after, "time": time] }
}

// MARK: - View

enum Field: Hashable {
    case submit, time, after, cancel
}

struct ContentView: View {
    @ObservedObject var model: Model
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @FocusState private var focus: Field?

    /// Parts of the preview, in order; the date is highlighted, the rest is secondary.
    private var previewParts: [(text: String, isDate: Bool)] {
        let date = (text: model.time ? "[YYMMDD-HHhMM]" : "[YYMMDD]", isDate: true)
        let name = (text: "[FileName]", isDate: false)
        let ext = (text: "[.extension]", isDate: false)
        return model.after ? [name, date, ext] : [date, name, ext]
    }

    var body: some View {
        DialogLayout(width: 516) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Get the \"Date Created\" information from the file to rename it.")
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add hours and minutes")
                        Text(verbatim: "[YYMMDD-HHhMM]")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    DialogSwitch(label: "Add hours and minutes", isOn: $model.time)
                        .focused($focus, equals: .time)
                }
                HStack(spacing: 12) {
                    Text("Position the information after the file name")
                    Spacer()
                    DialogSwitch(label: "Position the information after the file name", isOn: $model.after)
                        .focused($focus, equals: .after)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach(Array(previewParts.enumerated()), id: \.offset) { _, part in
                            Text(verbatim: part.text)
                                .foregroundStyle(part.isDate ? HierarchicalShapeStyle.primary : HierarchicalShapeStyle.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .quaternaryLabelColor)))
                }
                .padding(.top, 4)
            }
        } leading: {
            EmptyView()
        } trailing: {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .focused($focus, equals: .cancel)
            Button(action: onSubmit) {
                Text(verbatim: "Rename \(model.count) file(s)")
            }
            .keyboardShortcut(.defaultAction)
            .focused($focus, equals: .submit)
        }
        .modifier(TabOrder(order: [.submit, .time, .after, .cancel], focus: $focus))
    }
}

// MARK: - Shared dialog building blocks (same in the 3 apps, matches the Figma "_Modal")

/// Window chrome of the dialogs: close (= Cancel) and minimize enabled, zoom disabled.
@MainActor
func makeDialogWindow<Content: View>(title: String, rootView: Content) -> NSWindow {
    let controller = NSHostingController(rootView: rootView)
    controller.sizingOptions = .preferredContentSize  // window follows the content height
    let window = NSWindow(contentViewController: controller)
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.title = title
    window.standardWindowButton(.zoomButton)?.isEnabled = false  // no full screen for a dialog
    window.isReleasedWhenClosed = false
    window.level = .floating  // stay above the Finder window it was launched from
    window.center()
    return window
}

/// Main content (40 pt side margins) above the footer actions (20 pt margins):
/// optional leading actions on the left, Cancel / primary action on the right.
struct DialogLayout<Content: View, Leading: View, Trailing: View>: View {
    let width: CGFloat
    let content: Content
    let leading: Leading
    let trailing: Trailing

    init(width: CGFloat,
         @ViewBuilder content: () -> Content,
         @ViewBuilder leading: () -> Leading,
         @ViewBuilder trailing: () -> Trailing) {
        self.width = width
        self.content = content()
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
            HStack(spacing: 8) {
                leading
                Spacer()
                trailing
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)  // 20 + 12 = 32 pt between the switches and the buttons
            .padding(.bottom, 20)
        }
        .frame(width: width)
    }
}

/// "Label ............ value" line (label primary, value secondary, right aligned).
struct ValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
            Spacer(minLength: 12)
            Text(verbatim: value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Small switch with its label hidden visually but kept for VoiceOver.
struct DialogSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
    }
}

/// Cycles the focus through `order` with Tab / Shift-Tab (default action button first).
struct TabOrder<Field: Hashable>: ViewModifier {
    let order: [Field]
    var focus: FocusState<Field?>.Binding

    func body(content: Content) -> some View {
        content
            // Shift-Tab can arrive as the "backtab" character (U+0019) instead of Tab + Shift.
            .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")], phases: .down) { press in
                guard !order.isEmpty else { return .ignored }
                let backward = press.modifiers.contains(.shift) || press.key == KeyEquivalent("\u{19}")
                let index = focus.wrappedValue.flatMap { order.firstIndex(of: $0) }
                    ?? (backward ? 0 : order.count - 1)
                focus.wrappedValue = order[(index + (backward ? order.count - 1 : 1)) % order.count]
                return .handled
            }
            .onAppear {
                // Start on the first field; deferred so the window is key before focus is set.
                DispatchQueue.main.async { focus.wrappedValue = order.first }
            }
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let args = parseArgs()
    lazy var model = Model(args: args)
    var window: NSWindow!
    var finished = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let view = ContentView(
            model: model,
            onCancel: { [unowned self] in self.finish(cancelled: true) },
            onSubmit: { [unowned self] in self.finish(cancelled: false) }
        )
        window = makeDialogWindow(title: WINDOW_TITLE, rootView: view)
        window.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Write the result for the Python script (once), then quit.
    func finish(cancelled: Bool) {
        guard !finished else { return }
        finished = true
        var result: [String: Any] = ["cancelled": cancelled]
        if !cancelled { result.merge(model.result) { $1 } }
        if let out = args.out, let data = try? JSONSerialization.data(withJSONObject: result) {
            try? data.write(to: out)
        }
        NSApp.terminate(nil)
    }

    func windowWillClose(_ notification: Notification) {
        finish(cancelled: true)  // red close button = Cancel
    }
}

// MARK: - Notification mode

/// "--notify-title T --notify-body B --out F": post one macOS notification under
/// this app's name (instead of Script Editor's), write {"posted": true|false} to F, quit.
struct NotifyRequest {
    let title: String
    let body: String
    let out: URL?

    static func fromArguments() -> NotifyRequest? {
        var title: String?
        var body = ""
        var out: URL?
        var items = CommandLine.arguments.dropFirst().makeIterator()
        while let key = items.next() {
            guard key.hasPrefix("--"), let value = items.next() else { continue }
            switch key {
            case "--notify-title": title = value
            case "--notify-body": body = value
            case "--out": out = URL(fileURLWithPath: value)
            default: break
            }
        }
        return title.map { NotifyRequest(title: $0, body: body, out: out) }
    }
}

/// Asks macOS to show the banner even though this app is frontmost at that moment
/// (by default, notifications of the active app only go to Notification Center).
final class BannerPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}

@MainActor
final class Notifier: NSObject, NSApplicationDelegate {
    let request: NotifyRequest
    let presenter = BannerPresenter()
    var finished = false

    init(request: NotifyRequest) {
        self.request = request
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            finish(posted: await post())
        }
        Task { @MainActor in
            // Give up if the first-time permission prompt is left unanswered.
            try? await Task.sleep(for: .seconds(60))
            finish(posted: false)
        }
    }

    private func post() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        do {
            // First run only: macOS asks whether this app may send notifications.
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { return false }
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            try await center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                                       content: content, trigger: nil))
            // Stay alive a moment so macOS can ask the delegate how to present it.
            try? await Task.sleep(for: .seconds(1.5))
            return true
        } catch {
            return false  // e.g. notifications refused for this (locally signed) app
        }
    }

    /// Write the result for the Python script (once), then quit; the notification stays.
    private func finish(posted: Bool) {
        guard !finished else { return }
        finished = true
        if let out = request.out, let data = try? JSONSerialization.data(withJSONObject: ["posted": posted]) {
            try? data.write(to: out)
        }
        NSApp.terminate(nil)
    }
}

/// Launched with no arguments (e.g. by a click on one of its notifications): nothing to do.
@MainActor
final class Quitter: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

// Top-level code runs on the main thread; tell the compiler so it can create the
// @MainActor delegates synchronously.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate: NSApplicationDelegate  // kept alive by this scope while app.run() blocks
    if let request = NotifyRequest.fromArguments() {
        delegate = Notifier(request: request)
    } else if CommandLine.arguments.contains("--out") {
        delegate = AppDelegate()
    } else {
        delegate = Quitter()
    }
    app.delegate = delegate
    app.run()
}
