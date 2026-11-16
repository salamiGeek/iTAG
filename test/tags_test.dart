import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:itag/main.dart';
import 'package:itag/tags.dart';
import 'package:material_ui/material_ui.dart';

const earbuds = Tag('AA:00:00:00:00:01', 'iTAG');
const keys = Tag('AA:00:00:00:00:02', 'iTAG');

void main() {
  testWidgets('add a nearby tag, name it and open its ring controls', (
    tester,
  ) async {
    final gateway = TestGateway();
    await tester.binding.setSurfaceSize(const Size(390, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ITagApp(gateway: gateway));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '添加标签'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    gateway.stream.add((
      type: TagEventType.found,
      tag: earbuds,
      id: earbuds.id,
      error: null,
    ));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, '连接'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '耳机');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('耳机'), findsOneWidget);
    expect(find.text('电量 78%'), findsOneWidget);
    await tester.tap(find.text('响铃'));
    await tester.pumpAndSettle();
    expect(find.text('响铃指令已发送'), findsOneWidget);
    await tester.tap(find.text('停止响铃'));
    await tester.pumpAndSettle();
    expect(find.text('响铃指令已发送'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await gateway.stream.close();
  });

  test('connect, rename and reopen with the saved item name', () async {
    final gateway = TestGateway();
    final first = TagController(gateway);
    await first.initialize();
    expect(await first.connect(earbuds), isTrue);
    await first.rename(earbuds, '  耳机  ');
    first.dispose();

    final reopened = TagController(gateway);
    await reopened.initialize();
    expect(reopened.tags.single.name, '耳机');
    expect(reopened.connectedId, earbuds.id);
    expect(reopened.link?.battery, 78);
    expect(gateway.automaticConnections, [earbuds.id]);
    reopened.dispose();
    await gateway.stream.close();
  });

  test(
    'switching the active tag keeps both and opens one BLE connection',
    () async {
      final gateway = TestGateway();
      final controller = TagController(gateway);
      await controller.initialize();
      expect(await controller.connect(earbuds), isTrue);
      expect(await controller.connect(keys), isTrue);
      expect(controller.connectedId, keys.id);
      expect(controller.tags.map((tag) => tag.id), [earbuds.id, keys.id]);
      expect(gateway.library.lastUsed, keys.id);
      controller.dispose();
      await gateway.stream.close();
    },
  );

  test('an unavailable saved tag stays available for manual retry', () async {
    final gateway = TestGateway()
      ..library = (tags: [earbuds], lastUsed: earbuds.id)
      ..unavailable = true;
    final controller = TagController(gateway);
    await controller.initialize();
    expect(controller.tags.single.id, earbuds.id);
    expect(controller.connectedId, isNull);
    gateway.unavailable = false;
    expect(await controller.connect(earbuds), isTrue);
    expect(controller.connectedId, earbuds.id);
    controller.dispose();
    await gateway.stream.close();
  });

  test(
    'sends ring and stop to the active tag and clears state on disconnect',
    () async {
      final gateway = TestGateway();
      final controller = TagController(gateway);
      await controller.initialize();
      await controller.connect(earbuds);
      await controller.sendAlert(true);
      expect(controller.alertRequested, isTrue);
      await controller.sendAlert(false);
      expect(gateway.alerts, [(earbuds.id, true), (earbuds.id, false)]);
      expect(controller.alertRequested, isFalse);
      gateway.dropConnection(earbuds.id);
      expect(controller.connectedId, isNull);
      expect(controller.link, isNull);
      controller.dispose();
      await gateway.stream.close();
    },
  );

  test('manual disconnect keeps the name and closes the active link', () async {
    final gateway = TestGateway();
    final controller = TagController(gateway);
    await controller.initialize();
    await controller.connect(earbuds);
    await controller.rename(earbuds, '耳机');
    await controller.disconnect();
    expect(controller.connectedId, isNull);
    expect(controller.tags.single.name, '耳机');
    expect(gateway.active, isNull);
    controller.dispose();
    await gateway.stream.close();
  });
}

class TestGateway implements TagGateway {
  final stream = StreamController<TagEvent>.broadcast(sync: true);
  final automaticConnections = <String>[];
  final alerts = <(String, bool)>[];
  TagLibrary library = (tags: [], lastUsed: null);
  bool unavailable = false;
  String? active;

  @override
  Stream<TagEvent> get events => stream.stream;

  @override
  Future<TagLibrary> load() async {
    active = null;
    return library;
  }

  @override
  Future<void> save(TagLibrary value) async => library = value;

  @override
  Future<TagLink> connect(String id, {required bool automatic}) async {
    if (active != null) throw StateError('Existing connection was not closed');
    if (automatic) automaticConnections.add(id);
    if (unavailable) throw StateError('Tag unavailable');
    active = id;
    return (battery: 78, canRing: true);
  }

  @override
  Future<void> disconnect() async => active = null;

  @override
  Future<void> sendAlert(bool ring) async => alerts.add((active!, ring));

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  void dropConnection(String id) {
    active = null;
    stream.add((
      type: TagEventType.disconnected,
      tag: null,
      id: id,
      error: null,
    ));
  }
}
