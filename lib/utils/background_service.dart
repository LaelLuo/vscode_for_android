import 'dart:io';

import 'package:flutter_background/flutter_background.dart';

const _androidConfig = FlutterBackgroundAndroidConfig(
  notificationTitle: "VS Code",
  notificationText: "Background notification for keeping the VS Code running in the background",
);

final _canRun = Platform.isAndroid;

var _inited = false;

Future<void> initService() async {
  _inited = await FlutterBackground.initialize(androidConfig: _androidConfig);
}

Future<void> startService() async {
  if (!_canRun) return;
  if (!_inited) await initService();
  await FlutterBackground.enableBackgroundExecution();
}

Future<void> stopService() async {
  if (!_canRun) return;
  await FlutterBackground.disableBackgroundExecution();
}