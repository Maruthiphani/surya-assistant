import 'app_language.dart';

/// Localized UI strings for the core app chrome + spoken/notification
/// scaffolding (CLAUDE.md Phase 9). Hand-written per language (no cloud
/// translation — that would be a paid/LLM path). User content is passed through
/// verbatim via the `{task}`/`{place}` arguments, never translated.
///
/// Coverage is the high-visibility surface first (settings, home, voice,
/// confirmations, reminder notification); the rest is incremental.
abstract class AppStrings {
  const AppStrings();

  static AppStrings of(AppLanguage lang) {
    switch (lang) {
      case AppLanguage.english:
        return const _En();
      case AppLanguage.hindi:
        return const _Hi();
      case AppLanguage.telugu:
        return const _Te();
    }
  }

  // Settings
  String get settingsTitle;
  String get assistantSection;
  String get assistantNameLabel;
  String get remindersSection;
  String get defaultRadiusLabel;
  String get languageSection;
  String get languageLabel;
  String get save;
  String get settingsSaved;

  // Home
  String get speak;
  String get noRemindersTitle;
  String get noRemindersBody;

  // Voice capture
  String get voiceTitle;
  String get voicePrompt;
  String get voiceListening;
  String get voiceContinue;

  // Confirmations (user content interpolated, not translated)
  String confirmReach(String task, String place);
  String confirmTime(String task, String whenLabel);

  // Reminder notification
  String reminderTitle(String assistant);
  String nearBody(String place, String task);
}

class _En extends AppStrings {
  const _En();
  @override
  String get settingsTitle => 'Settings';
  @override
  String get assistantSection => 'Assistant';
  @override
  String get assistantNameLabel => 'Assistant name';
  @override
  String get remindersSection => 'Reminders';
  @override
  String get defaultRadiusLabel => 'Default radius (metres)';
  @override
  String get languageSection => 'Language';
  @override
  String get languageLabel => 'Hanu speaks and listens in';
  @override
  String get save => 'Save';
  @override
  String get settingsSaved => 'Settings saved.';
  @override
  String get speak => 'Speak';
  @override
  String get noRemindersTitle => 'No reminders yet';
  @override
  String get noRemindersBody =>
      'Tap the mic and say a reminder, or add one manually.';
  @override
  String get voiceTitle => 'Speak a reminder';
  @override
  String get voicePrompt => 'Tap the mic and say your reminder';
  @override
  String get voiceListening => 'Listening…';
  @override
  String get voiceContinue => 'Continue';
  @override
  String confirmReach(String task, String place) =>
      "Got it — I'll remind you to $task when you reach $place.";
  @override
  String confirmTime(String task, String whenLabel) =>
      "Got it — I'll remind you to $task on $whenLabel.";
  @override
  String reminderTitle(String assistant) => '$assistant reminder';
  @override
  String nearBody(String place, String task) =>
      "You're near $place — $task.";
}

class _Hi extends AppStrings {
  const _Hi();
  @override
  String get settingsTitle => 'सेटिंग्स';
  @override
  String get assistantSection => 'सहायक';
  @override
  String get assistantNameLabel => 'सहायक का नाम';
  @override
  String get remindersSection => 'रिमाइंडर';
  @override
  String get defaultRadiusLabel => 'डिफ़ॉल्ट दूरी (मीटर)';
  @override
  String get languageSection => 'भाषा';
  @override
  String get languageLabel => 'हनु इस भाषा में बोलता और सुनता है';
  @override
  String get save => 'सहेजें';
  @override
  String get settingsSaved => 'सेटिंग्स सहेजी गईं।';
  @override
  String get speak => 'बोलें';
  @override
  String get noRemindersTitle => 'अभी कोई रिमाइंडर नहीं';
  @override
  String get noRemindersBody =>
      'माइक दबाएँ और रिमाइंडर बोलें, या मैन्युअल रूप से जोड़ें।';
  @override
  String get voiceTitle => 'रिमाइंडर बोलें';
  @override
  String get voicePrompt => 'माइक दबाएँ और अपना रिमाइंडर बोलें';
  @override
  String get voiceListening => 'सुन रहा हूँ…';
  @override
  String get voiceContinue => 'आगे बढ़ें';
  @override
  String confirmReach(String task, String place) =>
      'ठीक है — जब आप $place पहुँचेंगे तो मैं आपको $task की याद दिलाऊँगा।';
  @override
  String confirmTime(String task, String whenLabel) =>
      'ठीक है — $whenLabel को मैं आपको $task की याद दिलाऊँगा।';
  @override
  String reminderTitle(String assistant) => '$assistant रिमाइंडर';
  @override
  String nearBody(String place, String task) =>
      'आप $place के पास हैं — $task।';
}

class _Te extends AppStrings {
  const _Te();
  @override
  String get settingsTitle => 'సెట్టింగ్‌లు';
  @override
  String get assistantSection => 'సహాయకుడు';
  @override
  String get assistantNameLabel => 'సహాయకుడి పేరు';
  @override
  String get remindersSection => 'రిమైండర్‌లు';
  @override
  String get defaultRadiusLabel => 'డిఫాల్ట్ దూరం (మీటర్లు)';
  @override
  String get languageSection => 'భాష';
  @override
  String get languageLabel => 'హనూ ఈ భాషలో మాట్లాడతాడు, వింటాడు';
  @override
  String get save => 'సేవ్ చేయి';
  @override
  String get settingsSaved => 'సెట్టింగ్‌లు సేవ్ అయ్యాయి.';
  @override
  String get speak => 'మాట్లాడండి';
  @override
  String get noRemindersTitle => 'ఇంకా రిమైండర్‌లు లేవు';
  @override
  String get noRemindersBody =>
      'మైక్ నొక్కి రిమైండర్ చెప్పండి, లేదా చేతితో జోడించండి.';
  @override
  String get voiceTitle => 'రిమైండర్ చెప్పండి';
  @override
  String get voicePrompt => 'మైక్ నొక్కి మీ రిమైండర్ చెప్పండి';
  @override
  String get voiceListening => 'వింటున్నాను…';
  @override
  String get voiceContinue => 'కొనసాగించు';
  @override
  String confirmReach(String task, String place) =>
      'సరే — మీరు $place చేరుకున్నప్పుడు $task గుర్తు చేస్తాను.';
  @override
  String confirmTime(String task, String whenLabel) =>
      'సరే — $whenLabel కు $task గుర్తు చేస్తాను.';
  @override
  String reminderTitle(String assistant) => '$assistant రిమైండర్';
  @override
  String nearBody(String place, String task) =>
      'మీరు $place దగ్గర ఉన్నారు — $task.';
}
