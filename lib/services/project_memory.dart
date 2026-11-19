import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/pet_state.dart';
import '../models/manual.dart';
import '../models/profile.dart';

/// One project "context window": its own chat thread and the facts the
/// pet decided to remember about it.
class ProjectContext {
  final String id;
  String name;
  final List<String> notes;
  final List<ChatMessage> chat;
  DateTime updatedAt;

  /// Closed from the tab bar: hidden, but kept (restore in Settings).
  bool archived;

  /// Name for display. The stored name of the general thread stays '일상'
  /// (it is saved data); the shown name follows the language.
  String get label => id == ProjectMemory.generalId
      ? Lang.t('일상', 'Daily', '日常')
      : (id == Manual.roomId ? Manual.title : name);

  ProjectContext({
    required this.id,
    required this.name,
    List<String>? notes,
    List<ChatMessage>? chat,
    DateTime? updatedAt,
    this.archived = false,
  })  : notes = notes ?? [],
        chat = chat ?? [],
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'notes': notes,
        'updatedAt': updatedAt.toIso8601String(),
        if (archived) 'archived': true,
        'chat': chat
            .map((m) => {
                  't': m.text,
                  'u': m.fromUser,
                  'at': m.at.toIso8601String(),
                  if (m.sticker != null) 's': m.sticker,
                })
            .toList(),
      };

  factory ProjectContext.fromJson(Map<String, dynamic> j) => ProjectContext(
        id: j['id'].toString(),
        name: (j['name'] ?? j['id']).toString(),
        notes: (j['notes'] is List ? j['notes'] as List : const []).map((e) => e.toString()).toList(),
        updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '') ??
            DateTime.now(),
        archived: j['archived'] == true,
        chat: (j['chat'] is List ? j['chat'] as List : const [])
            .whereType<Map>()
            .map((m) => ChatMessage(
                  text: '${m['t'] ?? ''}',
                  fromUser: m['u'] == true,
                  at: DateTime.tryParse(m['at']?.toString() ?? '') ??
                      DateTime.now(),
                  sticker: m['s']?.toString(),
                ))
            .toList(),
      );
}

/// Project-separated memory. "일상" is the default thread; the AI names a
/// project in its reply when the user is talking about one, and new names
/// open a new context automatically.
class ProjectMemory {
  static const generalId = 'general';
  static const maxChat = 200;
  static const maxNotes = 40;
  static const maxName = 40;

  /// What a model writes when it means "no particular project" (lower case).
  static const nothingWords = {
    '일상', 'daily', 'general', 'none', 'null', 'n/a', 'na', 'nil', 'undefined', '없음', '无', '-', '—',
  };

  final List<ProjectContext> projects = [
    ProjectContext(id: generalId, name: '일상'),
  ];
  String activeId = generalId;

  ProjectContext get active => projects.firstWhere(
      (p) => p.id == activeId && !p.archived,
      orElse: () => projects.first);

  /// Tabs shown in the 대화 tab (일상 first, then open projects).
  List<ProjectContext> get visible =>
      projects.where((p) => !p.archived).toList();

  List<ProjectContext> get archivedList =>
      projects.where((p) => p.archived).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// Opens the 📖 Manual room (Settings > Manual). The manual is its first
  /// message; it is posted again when missing or in another language.
  ProjectContext openManual() {
    var p = projects.where((x) => x.id == Manual.roomId).firstOrNull;
    if (p == null) {
      p = ProjectContext(id: Manual.roomId, name: 'Manual');
      projects.add(p);
    }
    p.archived = false;
    if (p.chat.isEmpty || p.chat.first.text != Manual.text) {
      p.chat
        ..clear()
        ..add(ChatMessage(text: Manual.text, fromUser: false, at: DateTime.now()))
        ..add(ChatMessage(text: Manual.welcome, fromUser: false, at: DateTime.now()));
    }
    activeId = p.id;
    return p;
  }

  /// Opens a new context window (or reopens one with the same name).
  ProjectContext? create(String name) {
    final p = resolve(name);
    if (p == null) return null;
    p.archived = false;
    p.updatedAt = DateTime.now();
    activeId = p.id;
    return p;
  }

  /// Closes a tab without deleting anything. 일상 can't be closed.
  bool archive(String id) {
    if (id == generalId) return false;
    final i = projects.indexWhere((p) => p.id == id);
    if (i < 0) return false;
    projects[i].archived = true;
    projects[i].updatedAt = DateTime.now(); // so the other Mac closes it too
    if (activeId == id) activeId = generalId;
    return true;
  }

  void restore(String id) {
    for (final p in projects) {
      if (p.id == id) {
        p.archived = false;
        p.updatedAt = DateTime.now();
        activeId = id;
      }
    }
  }

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/projects.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      // One broken entry (e.g. junk that came in through sync) is skipped,
      // never the whole file: the next save would erase every other room.
      final list = <ProjectContext>[];
      for (final e in (j['projects'] is List ? j['projects'] as List : const [])) {
        if (e is! Map) continue;
        try {
          list.add(ProjectContext.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {}
      }
      if (list.isNotEmpty) {
        projects
          ..clear()
          ..addAll(list);
        if (!projects.any((p) => p.id == generalId)) {
          projects.insert(0, ProjectContext(id: generalId, name: '일상'));
        }
      }
      activeId = (j['active'] ?? generalId).toString();
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'active': activeId,
        'projects': projects.map((p) => p.toJson()).toList(),
      }));
    } catch (_) {}
  }

  /// Finds a project by (case/space-insensitive) name, creating it if new.
  /// Returns null for empty names or the general thread.
  ProjectContext? resolve(String? name) {
    // One short line: the name becomes a tab label and a notes file name.
    var n = (name ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (n.length > maxName) n = n.substring(0, maxName).trim();
    if (n.isEmpty || nothingWords.contains(n.toLowerCase())) return null;
    String norm(String s) => s.replaceAll(' ', '').toLowerCase();
    for (final p in projects) {
      if (p.id == Manual.roomId) continue;
      if (norm(p.name) == norm(n)) {
        p.archived = false; // talking about it again reopens the tab
        return p;
      }
    }
    final p = ProjectContext(id: _newId(), name: n);
    projects.add(p);
    return p;
  }

  /// 'p<millis>', made unique when several are created in the same millisecond.
  String _newId() {
    final base = 'p${DateTime.now().millisecondsSinceEpoch}';
    var id = base, i = 1;
    while (projects.any((p) => p.id == id)) {
      id = '${base}_${i++}';
    }
    return id;
  }

  void addMessage(ProjectContext p, ChatMessage m) {
    p.chat.add(m);
    if (p.chat.length > maxChat) p.chat.removeRange(0, p.chat.length - maxChat);
    p.updatedAt = DateTime.now();
  }

  void remember(ProjectContext p, String? note) {
    // One line: notes are replayed into the prompt as "- note" bullets.
    final n = (note ?? '').replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();
    if (n.isEmpty || p.notes.contains(n)) return;
    p.notes.add(n);
    if (p.notes.length > maxNotes) p.notes.removeAt(0);
  }

  /// Context block for the system prompt: known project names plus the
  /// active project's remembered notes.
  String promptBlock() {
    final names = projects
        .where((p) => p.id != generalId && p.id != Manual.roomId && !p.archived)
        .map((p) => p.name);
    final a = active;
    return [
      Lang.t('알고 있는 프로젝트: ${names.isEmpty ? '(아직 없음)' : names.join(', ')}',
          'Known projects: ${names.isEmpty ? '(none yet)' : names.join(', ')}'),
      Lang.t('현재 대화방: ${a.name}', 'Current chat room: ${a.label}', '当前聊天室：${a.label}'),
      if (a.notes.isNotEmpty)
        Lang.t('기억해 둔 내용(${a.name}):\n- ${a.notes.join('\n- ')}',
            'Remembered notes (${a.label}):\n- ${a.notes.join('\n- ')}',
            '记住的内容（${a.label}）：\n- ${a.notes.join('\n- ')}'),
    ].join('\n');
  }
}
