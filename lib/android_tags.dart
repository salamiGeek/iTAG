import 'dart:convert';

import 'package:flutter/services.dart';

import 'tags.dart';

class AndroidTagGateway implements TagGateway {
  static const _methods = MethodChannel('itag/tags');
  static const _events = EventChannel('itag/tag_events');

  @override
  Stream<TagEvent> get events => _events.receiveBroadcastStream().map((value) {
    final event = (value as Map).cast<String, Object?>();
    return (
      type: TagEventType.values.byName(event['type'] as String),
      tag: event['type'] == 'found' ? _tagFromMap(event) : null,
      id: event['id'] as String?,
      error: event['error'] as String?,
    );
  });

  @override
  Future<TagLibrary> load() async {
    final value = await _call<String>('load');
    if (value == null) return (tags: <Tag>[], lastUsed: null);
    final library = jsonDecode(value) as Map<String, Object?>;
    final tags = (library['tags'] as List).cast<Map<String, Object?>>();
    return (
      tags: tags.map(_tagFromMap).toList(),
      lastUsed: library['lastUsed'] as String?,
    );
  }

  @override
  Future<void> save(TagLibrary library) => _call<void>(
    'save',
    jsonEncode({
      'tags': [
        for (final tag in library.tags)
          {
            'id': tag.id,
            'name': tag.advertisedName,
            'customName': tag.customName,
          },
      ],
      'lastUsed': library.lastUsed,
    }),
  );

  @override
  Future<void> startScan() => _call<void>('startScan');

  @override
  Future<void> stopScan() => _call<void>('stopScan');

  @override
  Future<TagLink> connect(String id, {required bool automatic}) async {
    final link = (await _call<Map>('connect', {
      'id': id,
      'automatic': automatic,
    }))!;
    return (battery: link['battery'] as int?, canRing: link['canRing'] == true);
  }

  @override
  Future<void> disconnect() => _call<void>('disconnect');

  @override
  Future<void> sendAlert(bool ring) =>
      _call<void>('sendAlert', ring ? 0x01 : 0x00);

  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw TagFailure(error.code, error.message);
    }
  }

  Tag _tagFromMap(Map<String, Object?> map) => Tag(
    map['id'] as String,
    map['name'] as String,
    customName: map['customName'] as String?,
  );
}
