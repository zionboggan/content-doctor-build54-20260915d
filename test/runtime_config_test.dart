import 'package:flutter_test/flutter_test.dart';
import 'package:iris/runtime_config.dart';

void main() {
  test('accepts bounded config and preserves order/visibility', () {
    final RuntimeConfig? config = RuntimeConfig.parse(<String, dynamic>{
      'schema_version': 1,
      'version': '2026-09-13.1',
      'copy': <String, String>{'empty_review': 'Nothing to review'},
      'sections': <String>['team', 'review', 'schedule'],
      'section_visibility': <String, bool>{'schedule': false},
      'refresh_interval_seconds': 10,
      'refresh_seconds': <String, int>{'review': 5, 'team': 7},
      'features': <String, bool>{'crew_chat': false, 'phone_upload': true},
    });
    expect(config, isNotNull);
    expect(config!.sections, <String>['team', 'review']);
    expect(config.refreshInterval.inSeconds, 15);
    expect(config.refreshFor('review').inSeconds, 5);
    expect(config.refreshFor('team').inSeconds, 7);
    expect(config.refreshFor('results').inSeconds, 15);
    expect(config.text('empty_review'), 'Nothing to review');
    expect(config.feature('crew_chat'), isFalse);
    expect(config.feature('phone_upload'), isTrue);
  });

  test('rejects unknown schema and unsafe copy', () {
    expect(
      RuntimeConfig.parse(<String, dynamic>{
        'schema_version': 2,
        'version': 'new',
      }),
      isNull,
    );
    expect(
      RuntimeConfig.parse(<String, dynamic>{
        'schema_version': 1,
        'version': 'new',
        'copy': <String, dynamic>{'x': 1},
      }),
      isNull,
    );
    expect(
      RuntimeConfig.parse(<String, dynamic>{
        'schema_version': 1,
        'version': 'new',
        'features': <String, bool>{'provider_publish': false},
      }),
      isNull,
    );
    expect(
      RuntimeConfig.parse(<String, dynamic>{
        'schema_version': 1,
        'version': 'new',
        'refresh_seconds': <String, int>{'studio': 10},
      }),
      isNull,
    );
  });
}
