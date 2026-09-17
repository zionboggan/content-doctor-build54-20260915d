import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          if (!RegExp(r'^[a-z0-9-]+$').hasMatch(name)) return false;
          final Directory folder = Directory('app-store-captures');
          await folder.create(recursive: true);
          await File('${folder.path}/$name.png').writeAsBytes(bytes);
          return true;
        },
  );
}
