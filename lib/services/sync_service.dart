import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import '../edition.dart';

/// Keeps two Macs in step through a folder both can see (iCloud Drive,
/// Dropbox, Google Drive, a NAS share ...). The owner picks it once in
/// Settings; the macOS side keeps a security-scoped bookmark
/// (SyncFolderChannel in MainFlutterWindow.swift).
///
/// Synced: chats and project memory, pet stats, profile, reminders, coins.
/// Never synced: AI keys (ai_config.json) and per-Mac settings (size,
/// volume, haptics). Files live in `<folder>/<Ed.dataFolder> Sync/<file>` wrapped as
/// {"savedAt", "device", "data"}.
class SyncService {
  static const _ch = MethodChannel('hoodimong/sync');
  static String get dirName => '${Ed.dataFolder} Sync';
  static const files = [
    'projects.json',
    'pet_state.json',
    'profile.json',
    'reminders.json',
    'portfolio.json',
  ];

  String? folder;
  DateTime? lastSync;
  String? lastError;

  /// False until this Mac has synced once: on the first sync the shared
  /// copy wins, so a fresh install never overwrites the other Mac's data.
  bool _joined = false;

  bool get ready => folder != null;
  String get device => Platform.localHostname;

  Future<void> init(Directory base) async {
    try {
      folder = await _ch.invokeMethod<String>('restore');
    } catch (_) {}
    try {
      final j = jsonDecode(await File('${base.path}/sync_state.json').readAsString());
      _joined = j['joined'] == true;
      lastSync = DateTime.tryParse(j['lastSync']?.toString() ?? '');
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

  /// One round: pull, merge, push. True when local files changed (the app
  /// must reload them).
  Future<bool> run(Directory base) async {
    if (!ready) return false;
    var changed = false;
    var okFiles = 0;
    lastError = null;
    // One unreadable file (junk in the shared folder, a half-written local
    // file) must not stop the others from syncing.
    for (final name in files) {
      try {
        if (await _syncFile(base, name)) changed = true;
        okFiles++;
      } catch (e) {
        lastError = '$name: $e';
      }
    }
    if (okFiles > 0) {
      _joined = true;
      lastSync = DateTime.now();
      try {
        await File('${base.path}/sync_state.json').writeAsString(jsonEncode({
          'joined': true,
          'lastSync': lastSync!.toIso8601String(),
        }));
      } catch (e) {
        lastError ??= '$e';
      }
    }
    return changed;
  }

  /// Pull, merge, push one file. True when the local copy changed.
  Future<bool> _syncFile(Directory base, String name) async {
    var changed = false;
    final local = File('${base.path}/$name');
    final localText = await local.exists() ? await local.readAsString() : null;
    final localData = localText == null ? null : jsonDecode(localText);
    final localAt = localText == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : await local.lastModified();

    final remoteText = await _ch.invokeMethod<String>('read', {'name': '$dirName/$name'});
    Map<String, dynamic>? wrap;
    try {
      if (remoteText != null) wrap = jsonDecode(remoteText) as Map<String, dynamic>;
    } catch (_) {}
    final remoteData = wrap?['data'];
    final remoteAt = DateTime.tryParse(wrap?['savedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);

    final merged = SyncMerge.file(name,
        local: localData,
        remote: remoteData,
        localAt: localAt,
        remoteAt: remoteAt,
        joined: _joined);
    if (merged == null) return false;

    final mergedText = jsonEncode(merged);
    if (localData == null || jsonEncode(localData) != mergedText) {
      await local.writeAsString(mergedText);
      changed = true;
    }
    final shared = SyncMerge.forShare(name, merged);
    if (remoteData == null || jsonEncode(remoteData) != jsonEncode(shared)) {
      await _ch.invokeMethod<bool>('write', {
        'name': '$dirName/$name',
        'text': jsonEncode({
          'savedAt': DateTime.now().toUtc().toIso8601String(),
          'device': device,
          'data': shared,
        }),
        'append': false,
      });
    }
    return changed;
  }
}

/// Merge rules, kept pure so they can be tested.
class SyncMerge {
  /// Per-Mac keys in pet_state.json that never travel.
  static const localOnly = {
    'cuesEnabled',
    'macFallback',
    'roam',
    'sfxVolume',
    'haptics',
    'speechMode',
    'petScale',
    'panelW',
    'panelH',
    'panelTheme',
    'chatFont',
    'chatFontScale',
    'replyStickers',
    'onboardingDone',
    'menuBarEnabled',
    'notifyEnabled',
    'briefedOn',
    'marketBriefed',
  };

  static const manualRoom = 'manual';
  static const maxChat = 200;
  static const maxNotes = 40;

  /// The merged content for this Mac, or null when there is nothing on
  /// either side.
  static dynamic file(String name,
      {required dynamic local,
      required dynamic remote,
      required DateTime localAt,
      required DateTime remoteAt,
      required bool joined}) {
    if (local == null && remote == null) return null;
    if (remote == null) return local;
    if (local == null) return name == 'pet_state.json' ? _shareable(remote) : remote;
    switch (name) {
      case 'projects.json':
        if (local is! Map || remote is! Map) return local is Map ? local : remote;
        return projects(Map<String, dynamic>.from(local), Map<String, dynamic>.from(remote));
      case 'pet_state.json':
        if (local is! Map || remote is! Map) return local is Map ? local : _shareable(remote);
        return petState(Map<String, dynamic>.from(local), Map<String, dynamic>.from(remote),
            joined: joined);
      default: // profile, reminders, coins: the later edit wins
        if (!joined) return remote;
        return remoteAt.isAfter(localAt) ? remote : local;
    }
  }

  /// What goes into the shared folder (the manual room stays per Mac, it
  /// follows each Mac's language).
  static dynamic forShare(String name, dynamic merged) {
    if (name == 'pet_state.json') return _shareable(merged);
    if (name != 'projects.json') return merged;
    final m = Map<String, dynamic>.from(merged as Map);
    m['projects'] =
        (m['projects'] as List).where((p) => p['id'] != manualRoom).toList();
    m.remove('active');
    return m;
  }

  /// pet_state.json without the per-Mac keys (size, volume, theme ...).
  static dynamic _shareable(dynamic j) => j is Map
      ? {
          for (final e in j.entries)
            if (!localOnly.contains(e.key)) e.key: e.value,
        }
      : j;

  /// Timestamp as an instant; null when missing or unreadable.
  static DateTime? _t(Object? v) => DateTime.tryParse('${v ?? ''}');

  /// Chats are combined (nothing lost when both Macs were used); name and
  /// archived state follow the project's later update.
  static Map<String, dynamic> projects(
      Map<String, dynamic> local, Map<String, dynamic> remote) {
    final byId = <String, Map<String, dynamic>>{};
    final order = <String>[];
    Iterable<Map<String, dynamic>> entries(Object? list) sync* {
      if (list is! List) return;
      for (final p in list) {
        if (p is! Map) continue;
        final id = p['id'];
        if (id == null || '$id'.isEmpty) continue;
        yield {...Map<String, dynamic>.from(p), 'id': '$id'};
      }
    }

    for (final m in entries(local['projects'])) {
      final id = m['id'] as String;
      if (byId.containsKey(id)) continue; // a duplicated id: keep the first
      byId[id] = m;
      order.add(id);
    }
    final now = DateTime.now();
    // A Mac with a wrong clock must not make a project's updatedAt (which
    // decides who wins) unbeatable for the other Mac.
    final latest = now.add(const Duration(days: 1));
    DateTime cap(DateTime t) => t.isAfter(latest) ? now : t;
    for (final r in entries(remote['projects'])) {
      final id = r['id'] as String;
      if (id == manualRoom) continue;
      final l = byId[id];
      if (l == null) {
        byId[id] = r;
        order.add(id);
        continue;
      }
      final lAt = _t(l['updatedAt']) ?? DateTime(2000);
      final rAt = _t(r['updatedAt']) ?? DateTime(2000);
      final newer = rAt.isAfter(lAt) ? r : l;
      final seen = <String>{};
      final chat = <(DateTime, int, Map<String, dynamic>)>[];
      for (final c in [
        ...((l['chat'] is List) ? l['chat'] as List : const []),
        ...((r['chat'] is List) ? r['chat'] as List : const [])
      ]) {
        if (c is! Map) continue;
        final m = Map<String, dynamic>.from(c);
        final at = _t(m['at']);
        final key = '${at?.toUtc().microsecondsSinceEpoch ?? m['at']}|${m['u']}|${m['t']}';
        if (seen.add(key)) chat.add((at ?? DateTime(2000), chat.length, m));
      }
      // by instant (formats and time zones may differ); ties keep arrival order
      chat.sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
      final notes = <String>[];
      for (final n in [
        ...((l['notes'] is List) ? l['notes'] as List : const []),
        ...((r['notes'] is List) ? r['notes'] as List : const [])
      ]) {
        final t = '${n ?? ''}';
        if (t.isNotEmpty && !notes.contains(t)) notes.add(t);
      }
      final chats = [for (final c in chat) c.$3];
      byId[id] = {
        ...newer,
        'chat': chats.length > maxChat ? chats.sublist(chats.length - maxChat) : chats,
        'notes': notes.length > maxNotes ? notes.sublist(notes.length - maxNotes) : notes,
        'updatedAt': cap(rAt.isAfter(lAt) ? rAt : lAt).toIso8601String(),
      };
    }
    return {
      'active': local['active'] ?? remote['active'],
      'projects': [for (final id in order) byId[id]],
    };
  }

  /// Stats come from whichever Mac saw the pet last; size, volume and other
  /// per-Mac settings stay as they are here.
  static Map<String, dynamic> petState(
      Map<String, dynamic> local, Map<String, dynamic> remote,
      {required bool joined}) {
    // Beyond a day ahead is a wrong clock, not a real care action: it
    // would otherwise beat the other Mac forever.
    final latest = DateTime.now().add(const Duration(days: 1));
    DateTime at(Map m, String k) {
      final t = DateTime.tryParse(m[k]?.toString() ?? '');
      return t == null || t.isAfter(latest) ? DateTime(2000) : t;
    }
    // A care action (feed, play, ...) beats a Mac that merely kept the
    // pet open; otherwise the later save wins.
    final lCare = at(local, 'careAt'), rCare = at(remote, 'careAt');
    final remoteWins = !joined ||
        rCare.isAfter(lCare) ||
        (rCare == lCare && at(remote, 'lastSeen').isAfter(at(local, 'lastSeen')));
    if (!remoteWins) return local;
    return {
      ...local,
      for (final e in remote.entries)
        if (!localOnly.contains(e.key)) e.key: e.value,
    };
  }
}
