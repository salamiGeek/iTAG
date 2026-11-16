import 'dart:async';

import 'package:flutter/foundation.dart';

typedef TagLink = ({int? battery, bool canRing});

enum TagEventType { found, scanEnded, disconnected }

typedef TagEvent = ({TagEventType type, Tag? tag, String? id, String? error});

class Tag {
  const Tag(this.id, this.advertisedName, {this.customName});

  final String id;
  final String advertisedName;
  final String? customName;
  String get name => customName ?? advertisedName;
}

typedef TagLibrary = ({List<Tag> tags, String? lastUsed});

abstract interface class TagGateway {
  Stream<TagEvent> get events;
  Future<TagLibrary> load();
  Future<void> save(TagLibrary library);
  Future<void> startScan();
  Future<void> stopScan();
  Future<TagLink> connect(String id, {required bool automatic});
  Future<void> disconnect();
  Future<void> sendAlert(bool ring);
}

class TagController extends ChangeNotifier {
  TagController(this._gateway);

  final TagGateway _gateway;
  final _tags = <String, Tag>{};
  final _nearby = <String, Tag>{};
  StreamSubscription<TagEvent>? _events;
  String? _lastUsed;
  bool _disposed = false;

  List<Tag> get tags => List.unmodifiable(_tags.values);
  List<Tag> get nearby => List.unmodifiable(_nearby.values);
  String? connectedId;
  String? connectingId;
  TagLink? link;
  bool alertRequested = false;
  bool loading = true;
  bool scanning = false;
  bool sendingAlert = false;
  bool editing = false;
  bool disconnecting = false;
  String? error;

  bool get busy =>
      loading ||
      connectingId != null ||
      sendingAlert ||
      editing ||
      disconnecting;

  Future<void> initialize() async {
    _events = _gateway.events.listen(
      _onEvent,
      onError: (Object failure) {
        scanning = false;
        error = _message(failure, '蓝牙连接状态暂时无法读取。');
        _changed();
      },
    );
    try {
      final library = await _gateway.load();
      _tags.addEntries(library.tags.map((tag) => MapEntry(tag.id, tag)));
      _lastUsed = library.lastUsed;
    } catch (failure) {
      error = _message(failure, '无法读取已保存的标签。');
    } finally {
      loading = false;
      _changed();
    }
    await resume();
  }

  Future<void> resume() async {
    final lastTag = _tags[_lastUsed];
    if (!_disposed && lastTag != null && connectedId == null && !scanning) {
      await _connect(lastTag, automatic: true);
    }
  }

  Future<bool> connect(Tag tag) => _connect(tag, automatic: false);

  Future<void> disconnect() async {
    if (busy || connectedId == null) return;
    disconnecting = true;
    error = null;
    _changed();
    try {
      await _disconnect();
    } catch (failure) {
      error = _message(failure, '无法断开标签，请重试。');
    } finally {
      disconnecting = false;
      _changed();
    }
  }

  Future<void> _disconnect() async {
    if (alertRequested && link?.canRing == true) {
      await _gateway.sendAlert(false);
      alertRequested = false;
    }
    await _gateway.disconnect();
    _clearConnection();
  }

  Future<bool> _connect(Tag tag, {required bool automatic}) async {
    if (busy) return false;
    if (connectedId == tag.id) return true;
    connectingId = tag.id;
    error = null;
    _changed();
    try {
      await stopScan();
      if (connectedId != null) await _disconnect();
      final newLink = await _gateway.connect(tag.id, automatic: automatic);
      if (_disposed || connectingId != tag.id) return false;
      connectedId = tag.id;
      link = newLink;
      final updated = {..._tags, tag.id: _tags[tag.id] ?? tag};
      try {
        await _store(updated, tag.id);
      } catch (failure) {
        // The live connection remains useful even if local storage fails.
        error = _message(failure, '已连接，但无法保存标签。');
        _tags.addAll(updated);
        _lastUsed = tag.id;
      }
      return connectedId == tag.id;
    } catch (failure) {
      if (failure is! TagFailure || failure.code != 'background') {
        error = _message(failure, '连接失败。请让标签靠近手机后重试。');
      }
      return false;
    } finally {
      connectingId = null;
      _changed();
    }
  }

  Future<void> startScan() async {
    if (busy || scanning) return;
    _nearby.clear();
    error = null;
    scanning = true;
    _changed();
    try {
      await _gateway.startScan();
    } catch (failure) {
      scanning = false;
      error = _message(failure, '无法搜索标签，请检查蓝牙后重试。');
      _changed();
    }
  }

  Future<void> stopScan() async {
    if (!scanning) return;
    scanning = false;
    _changed();
    await _gateway.stopScan();
  }

  Future<void> rename(Tag tag, String name) async {
    final existing = _tags[tag.id];
    if (busy || existing == null) return;
    final trimmed = name.trim();
    final updated = Tag(
      existing.id,
      existing.advertisedName,
      customName: trimmed.isEmpty ? null : trimmed,
    );
    editing = true;
    error = null;
    _changed();
    try {
      await _store({..._tags, tag.id: updated}, _lastUsed);
    } catch (failure) {
      error = _message(failure, '名称保存失败，请重试。');
    } finally {
      editing = false;
      _changed();
    }
  }

  Future<void> sendAlert(bool ring) async {
    final id = connectedId;
    if (busy || id == null || link?.canRing != true) return;
    sendingAlert = true;
    error = null;
    _changed();
    try {
      await _gateway.sendAlert(ring);
      if (connectedId == id) alertRequested = ring;
    } catch (failure) {
      error = _message(failure, '指令发送失败，请重试。');
    } finally {
      sendingAlert = false;
      _changed();
    }
  }

  Future<void> _store(Map<String, Tag> tags, String? lastUsed) async {
    await _gateway.save((tags: tags.values.toList(), lastUsed: lastUsed));
    _tags
      ..clear()
      ..addAll(tags);
    _lastUsed = lastUsed;
  }

  void _onEvent(TagEvent event) {
    switch (event.type) {
      case TagEventType.found:
        final tag = event.tag!;
        if (!scanning || _nearby.containsKey(tag.id)) return;
        _nearby[tag.id] = tag;
      case TagEventType.scanEnded:
        if (!scanning) return;
        scanning = false;
        error = event.error;
      case TagEventType.disconnected:
        if (connectedId != event.id) return;
        _clearConnection();
    }
    _changed();
  }

  void _clearConnection() {
    connectedId = null;
    link = null;
    alertRequested = false;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events?.cancel());
    super.dispose();
  }
}

class TagFailure implements Exception {
  const TagFailure(this.code, this.message);

  final String code;
  final String? message;
}

String _message(Object failure, String fallback) =>
    failure is TagFailure ? failure.message ?? fallback : fallback;
