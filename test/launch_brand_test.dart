import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native launch screen uses the current doctor artwork', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final launch = File(
      'ios/Runner/Base.lproj/DoctorLaunch.storyboard',
    ).readAsStringSync();
    expect(plist, contains('<string>DoctorLaunch</string>'));
    expect(project, contains('Base.lproj/DoctorLaunch.storyboard'));
    expect(project, isNot(contains('LaunchScreen.storyboard')));
    expect(launch, contains('image="DoctorLaunch"'));
    expect(launch, isNot(contains('LaunchImage')));
    expect(launch, contains('contentMode="scaleAspectFit"'));
    expect(launch, contains('constant="112"'));
    expect(
      File(
        'ios/Runner/Assets.xcassets/DoctorLaunch.imageset/DoctorLaunch.png',
      ).readAsBytesSync(),
      File('assets/doctor-icon.png').readAsBytesSync(),
    );
  });
}
