// Switching the editor to a Gabe account used to reset captions to the
// generic white/68px style, discarding his repeatedly-confirmed spec
// (2026-09-11 caption profile, corroborated by MASTER-PROMPT.md and the
// A-word-v6 review): 160px centered Roboto Condensed Regular, butter yellow
// #FFEBA8, no outline. Nothing enforced that default -- whoever edited for
// his accounts had to remember to pick it by hand every time. The account
// dropdown's onChanged and NativeReelEditor's initState both now call
// captionDefaultsForAccount() instead of hardcoding the generic style, so
// this is exercised as a plain unit test on the pure mapping, not through
// widget navigation.

import 'package:flutter_test/flutter_test.dart';
import 'package:iris/native_editor.dart';

void main() {
  test('Gabe\'s two active accounts default to his confirmed caption spec', () {
    for (final String account in <String>[
      '@barcrawling',
      '@barcrawls.arizona',
    ]) {
      final CaptionDefaults d = captionDefaultsForAccount(account);
      expect(d.style, 'center_yellow', reason: account);
      expect(d.color, '#FFEBA8', reason: account);
      expect(d.sizePx, 160, reason: account);
    }
  });

  test(
    'every other account, including the collect-only Gabe one, gets the generic default',
    () {
      for (final String account in <String>['@zionboggan', '@gabejlove']) {
        final CaptionDefaults d = captionDefaultsForAccount(account);
        expect(d.style, 'center_white', reason: account);
        expect(d.color, '#FFFFFF', reason: account);
        expect(d.sizePx, 68, reason: account);
      }
    },
  );
}
