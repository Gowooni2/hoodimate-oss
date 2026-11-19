import 'package:flutter/services.dart';
import '../edition.dart';

/// Notes saved as Markdown into a folder the owner picks once (their
/// Obsidian vault on the NAS). The macOS side keeps a security-scoped
/// bookmark, see NotesFolderChannel in macos/Runner/MainFlutterWindow.swift.
///
/// Files: <folder>/<Ed.dataFolder>/<대화방 이름>.md, one bullet per note.
class Notes {
  static const _ch = MethodChannel('hoodimong/notes');

  /// Picked folder path, null until the owner chooses one.
  String? folder;

  bool get ready => folder != null;

  Future<void> init() async {
    try {
      folder = await _ch.invokeMethod<String>('restore');
    } catch (_) {}
  }

  Future<String?> pick() async {
    try {
      final p = await _ch.invokeMethod<String>('pick');
      if (p != null) folder = p;
      return p;
    } catch (_) {
      return null;
    }
  }

  static String fileFor(String project) {
    final safe = project.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return '${Ed.dataFolder}/${safe.isEmpty ? '일상' : safe}.md';
  }

  static String line(String text, DateTime at) {
    final d = at.toIso8601String();
    final oneLine = text.trim().replaceAll(RegExp(r'\s*\n\s*'), ' / ');
    return '- ${d.substring(0, 10)} ${d.substring(11, 16)} · $oneLine\n';
  }

  /// Appends one bullet to the project's note file. False if no folder.
  Future<bool> append(String project, String text, {DateTime? at}) async {
    if (!ready || text.trim().isEmpty) return false;
    try {
      return await _ch.invokeMethod<bool>('write', {
            'name': fileFor(project),
            'text': line(text, at ?? DateTime.now()),
            'append': true,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// "/노트 장보기 목록: 우유" -> save that text.
  /// "/노트", "이거 노트에 저장해줘", "노트해줘" -> save the pet's last reply
  /// (returned as an empty string). Null = not a note command.
  static String? parseCommand(String input) {
    final s = input.trim();
    final slash = RegExp(r'^/(노트|메모|note)\s*', caseSensitive: false).firstMatch(s);
    if (slash != null) return s.substring(slash.end).trim();
    final ask = RegExp(r'(노트|메모|옵시디언)(에|로)?\s*(저장|기록|적어)\s*(해\s*줘|해|해\s*줄래|둬|놔)?|노트\s*해\s*줘|메모\s*해\s*줘');
    final en = RegExp(
            r'^(please\s+)?(save|add|put|write)\s+(.*?)\s*(to|in|into|on)\s+(my\s+)?notes?[.!]*$|^(note|jot)\s+(this|that|it)\s+down[.!]*$|^take\s+a\s+note[.!]*$',
            caseSensitive: false)
        .firstMatch(s);
    if (en != null) {
      final what = (en.group(3) ?? '').trim();
      return RegExp(r'^(this|that|it|the last (reply|answer))?$', caseSensitive: false)
              .hasMatch(what)
          ? ''
          : what;
    }
    final m = ask.firstMatch(s);
    if (m == null) return null;
    // "우유 사기 메모해줘" -> "우유 사기"; "이거 노트에 저장해" -> last reply
    final rest = s
        .replaceRange(m.start, m.end, ' ')
        .replaceAll(RegExp(r'^(이거|이것|방금\s*(거|꺼|내용|말)?|이 내용|그거|위에\s*(거|꺼)?)\s*'), '')
        .replaceAll(RegExp(r'(을|를|좀)\s*$'), '')
        .trim();
    final pointer = RegExp(r'^(이거|이것|방금(거|꺼| 내용| 말)?|이 내용|그거|위에 ?거)?$');
    return pointer.hasMatch(rest) ? '' : rest;
  }
}
