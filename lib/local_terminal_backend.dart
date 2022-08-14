import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_pty/flutter_pty.dart';
import 'package:global_repository/global_repository.dart';
import 'package:xterm/terminal/terminal_backend.dart';

const _lineSplitter = LineSplitter();

class LocalTerminalBackend extends TerminalBackend {
  final Map<String, String> _envir;
  late final Completer _initCompleter;
  late final Pty _pty;
  late final Stream<String> output;
  late final Stream<String> lines;

  LocalTerminalBackend(this._envir, bool needInitTermial) {
    _pty = Pty.start(
      needInitTermial ? '/system/bin/sh' : '${RuntimeEnvir.binPath}/bash',
      arguments: [],
      environment: _envir,
      workingDirectory: RuntimeEnvir.homePath,
    );
    _initCompleter = Completer();
    output = _pty.output.cast<List<int>>().transform(utf8.decoder).asBroadcastStream();
    lines = output.transform(_lineSplitter).asBroadcastStream();
    lines.listen((event) => Log.d('[pty] ${jsonEncode(event)}'));
    exec('pty inited').then(_initCompleter.complete);
  }

  Future get inited => _initCompleter.future;

  @override
  Future<int> get exitCode => _pty.exitCode;

  @override
  void init() {}

  @override
  Stream<String> get out => output;

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {
    _pty.resize(width, height);
  }

  @override
  void write(String input) {
    _pty.write(utf8.encode(input) as Uint8List);
  }

  @override
  void terminate() => _pty.kill();

  @override
  void ackProcessed() {}

  Future<void> exec(String finishTag, [String? command]) async {
    final completer = Completer();
    StreamSubscription? sub;
    sub = lines.listen((e) {
      if (e != finishTag) return;
      sub?.cancel();
      completer.complete();
    });
    if (command != null) write('$command\n');
    write('echo "$finishTag"\n');
    await completer.future;
  }
}
