import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:itag/android_tags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sends the iTAG alarm level 01 to ring and 00 to stop', () async {
    const channel = MethodChannel('itag/tags');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final writes = <Object?>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'sendAlert');
      writes.add(call.arguments);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final gateway = AndroidTagGateway();
    await gateway.sendAlert(true);
    await gateway.sendAlert(false);

    expect(writes, [0x01, 0x00]);
  });
}
