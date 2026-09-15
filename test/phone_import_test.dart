import 'package:flutter_test/flutter_test.dart';
import 'package:iris/phone_import.dart';

void main() {
  test('phone import rejects an oversized file before upload', () {
    expect(
      phoneImportValidationMessage(
        account: '@zionboggan',
        kind: PhoneImportKind.video,
        name: 'take.mp4',
        bytes: phoneImportMaxBytes + 1,
      ),
      'Choose a file smaller than 250 MB.',
    );
  });

  test('phone import accepts an in-limit matching type', () {
    expect(
      phoneImportValidationMessage(
        account: '@zionboggan',
        kind: PhoneImportKind.audio,
        name: 'voice note.M4A',
        bytes: 42,
      ),
      isNull,
    );
  });

  test('phone import keeps audio and video types separate', () {
    expect(
      phoneImportValidationMessage(
        account: '@zionboggan',
        kind: PhoneImportKind.audio,
        name: 'reel.mov',
        bytes: 42,
      ),
      'Choose an audio file.',
    );
  });

  test('a confirmed receipt has a human fallback message', () {
    final PhoneImportReceipt receipt = PhoneImportReceipt.fromJson(
      <String, dynamic>{
        'ok': true,
        'kind': 'video',
        'message': '',
        'item': <String, dynamic>{'id': 'clip-1'},
      },
    );
    expect(receipt.message, 'Video added to your library.');
    expect(receipt.item['id'], 'clip-1');
  });
}
