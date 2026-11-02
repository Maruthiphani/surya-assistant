import AppIntents
import Foundation

/// Shared location for the reminder phrase handed off from a Siri Shortcut /
/// App Intent to the Flutter app. AppDelegate reads this and forwards it to
/// Flutter over the `surya/intents` method channel (CLAUDE.md Phase 5).
enum SuryaIntentStore {
    static let pendingKey = "surya.pendingReminderText"

    static func store(_ text: String) {
        UserDefaults.standard.set(text, forKey: pendingKey)
    }

    /// Returns the pending text and clears it (consume-once semantics).
    static func consume() -> String? {
        let defaults = UserDefaults.standard
        guard let text = defaults.string(forKey: pendingKey), !text.isEmpty else {
            return nil
        }
        defaults.removeObject(forKey: pendingKey)
        return text
    }
}

/// "Tell <name> to remind me…" — captures a free-form reminder phrase and opens
/// the app, where Flutter pre-fills the capture screen and parses it locally
/// (CLAUDE.md §9). We stash the phrase and let the app open; the actual parse,
/// confirmation and save happen in Flutter (no LLM in this native path).
@available(iOS 16.0, *)
struct AddReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a reminder"
    static var description = IntentDescription(
        "Capture a reminder by voice and open the app to confirm it."
    )

    // Bring the app to the foreground so Flutter can show the confirmation.
    static var openAppWhenRun: Bool = true

    @Parameter(
        title: "Reminder",
        requestValueDialog: "What should I remind you about?"
    )
    var phrase: String

    func perform() async throws -> some IntentResult {
        SuryaIntentStore.store(phrase)
        return .result()
    }
}

/// Registers the Siri phrases that invoke the intent. The spoken "<name>" is
/// the app name here (Siri phrases are static at build time and can't use the
/// user-chosen assistant name); the in-app UI still uses the chosen name.
@available(iOS 16.0, *)
struct SuryaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddReminderIntent(),
            phrases: [
                "Tell \(.applicationName) to remind me",
                "Ask \(.applicationName) to remind me",
                "Add a reminder in \(.applicationName)"
            ],
            shortTitle: "Add a reminder",
            systemImageName: "mappin.and.ellipse"
        )
    }
}
