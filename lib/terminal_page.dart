import 'dart:async';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:global_repository/global_repository.dart';
import 'package:vscode_for_android/local_terminal_backend.dart';
import 'package:vscode_for_android/utils/background_service.dart';
import 'package:xterm/flutter.dart';
import 'package:xterm/theme/terminal_theme.dart';
import 'package:xterm/xterm.dart';
import 'config.dart';
import 'http_handler.dart';
import 'utils/plugin_util.dart';
import 'script.dart';

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  // 环境变量
  late final Map<String, String> envir;
  late final LocalTerminalBackend ptyBackend;
  late final Terminal terminal;
  final initedCompleter = Completer();
  ValueNotifier<bool> vsCodeStaring = ValueNotifier(true);
  ValueNotifier<bool> background = ValueNotifier(false);

  // 是否存在bash文件
  bool hasBash() {
    final File bashFile = File('${RuntimeEnvir.binPath}/bash');
    return bashFile.existsSync();
  }

  Future<void> checkVersion() async {
    try {
      final response = await Dio().get('https://api.github.com/repos/coder/code-server/releases/latest');
      version = response.data['tag_name'].toString().substring(1);
    } on Exception catch (e) {
      Log.e('checkVersion error: $e');
      // await checkVersion();
    }
  }

  Future<void> initEnv() async {
    envir = Map.from(Platform.environment);
    envir['HOME'] = RuntimeEnvir.homePath!;
    envir['TERMUX_PREFIX'] = RuntimeEnvir.usrPath!;
    envir['TERM'] = 'xterm-256color';
    envir['PATH'] = RuntimeEnvir.path!;
    final ldPreloadPath = '${RuntimeEnvir.usrPath}/lib/libtermux-exec.so';
    if (File(ldPreloadPath).existsSync()) envir['LD_PRELOAD'] = ldPreloadPath;
    Directory(RuntimeEnvir.binPath!).createSync(recursive: true);
    final dioPath = '${RuntimeEnvir.binPath}/dart_dio';
    if (File(dioPath).existsSync()) return;
    File(dioPath).writeAsStringSync(Config.dioScript);
    await exec('chmod +x $dioPath');
  }

  Future<void> createPtyTerm() async {
    var needInitTermial = false;
    if (Platform.isAndroid) await PermissionUtil.requestStorage();
    await initEnv();
    if (Platform.isAndroid && !hasBash()) needInitTermial = true;
    ptyBackend = LocalTerminalBackend(
      envir,
      initedCompleter,
      needInitTermial,
    );
    terminal = Terminal(
      maxLines: 1000,
      backend: ptyBackend,
      theme: Platform.isAndroid ? android : theme,
    );
    await Future.wait([checkVersion(), initedCompleter.future]);
    vsCodeStartWhenSuccessBind();
    if (needInitTermial) {
      await initTerminal();
    } else {
      ptyBackend.write(startVsCodeScript);
      ptyBackend.write('start_vs_code\n');
    }
  }

  Future<void> vsCodeStartWhenSuccessBind() async {
    final vscodeCompleter = Completer();
    StreamSubscription? sub;
    sub = ptyBackend.output.listen((event) {
      final lastLine = event.trim();
      if (lastLine.startsWith('dart_dio')) {
        HttpHandler.handDownload(
          controller: terminal,
          cmdLine: lastLine,
        );
      }
      void finish() {
        vscodeCompleter.complete();
        sub?.cancel();
        vsCodeStaring.value = false;
      }

      if (lastLine.contains('http://0.0.0.0:10000')) finish();
      if (lastLine.contains('already')) finish();
    });
    await vscodeCompleter.future;
    // PlauginUtil.openWebView();
  }

  Future<void> initTerminal() async {
    ptyBackend.write(initShell);
    Directory(RuntimeEnvir.tmpPath!).createSync(recursive: true);
    Directory(RuntimeEnvir.homePath!).createSync(recursive: true);
    await AssetsUtils.copyAssetToPath(
      'assets/bootstrap-aarch64.zip',
      '${RuntimeEnvir.tmpPath}/bootstrap-aarch64.zip',
    );
    await AssetsUtils.copyAssetToPath(
      'assets/proot-distro.zip',
      '${RuntimeEnvir.homePath}/proot-distro.zip',
    );
    Directory('$prootDistroPath/dlcache').createSync(recursive: true);
    await AssetsUtils.copyAssetToPath(
      'assets/ubuntu-aarch64-pd-v2.3.1.tar.xz',
      '$prootDistroPath/dlcache/ubuntu-aarch64-pd-v2.3.1.tar.xz',
    );
    await unzipBootstrap('${RuntimeEnvir.tmpPath}/bootstrap-aarch64.zip');
    ptyBackend.write('initApp\n');
  }

  Future<void> unzipBootstrap(String modulePath) async {
    // Read the Zip file from disk.
    final bytes = File(modulePath).readAsBytesSync();
    // Decode the Zip file
    final archive = ZipDecoder().decodeBytes(bytes);
    // Extract the contents of the Zip archive to disk.
    final int total = archive.length;
    int count = 0;
    // print('total -> $total count -> $count');
    for (final file in archive) {
      final filename = file.name;
      final String path = '${RuntimeEnvir.usrPath}/$filename';
      Log.d(path);
      if (file.isFile) {
        final data = file.content as List<int>;
        await File(path).create(recursive: true);
        await File(path).writeAsBytes(data);
      } else {
        Directory(path).create(
          recursive: true,
        );
      }
      count++;
      Log.d('total -> $total count -> $count');
      setState(() {});
    }
    File(modulePath).delete();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    createPtyTerm();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: initedCompleter.future,
      builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox();
        }
        return WillPopScope(
          onWillPop: () async {
            ptyBackend.write('\x03');
            return true;
          },
          child: Stack(
            children: [
              SafeArea(child: TerminalView(terminal: terminal)),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildButton(
                      context,
                      ValueListenableBuilder(
                        valueListenable: vsCodeStaring,
                        builder: (BuildContext context, bool value, Widget? child) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (value)
                                SizedBox(
                                  width: 18.w,
                                  height: 18.w,
                                  child: CircularProgressIndicator(
                                    color: Theme.of(context).primaryColor,
                                    strokeWidth: 2.w,
                                  ),
                                ),
                              if (value)
                                const SizedBox(
                                  width: 8,
                                ),
                              Text(
                                value ? 'VS Code 启动中...' : '打开VS Code窗口',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                  fontSize: 16.w,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      () {
                        if (vsCodeStaring.value) return;
                        PlauginUtil.openWebView();
                      },
                    ),
                    const SizedBox(height: 10),
                    buildButton(
                      context,
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder(
                            valueListenable: background,
                            builder: (BuildContext context, bool value, Widget? child) {
                              return Text(
                                value ? '关闭前台服务' : '开启前台服务',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                  fontSize: 16.w,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      () async {
                        final value = background.value;
                        if (value) {
                          await stopService();
                        } else {
                          await startService();
                        }
                        background.value = !value;
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildButton(
    BuildContext context,
    Widget child,
    GestureTapCallback onTap,
  ) {
    return Material(
      color: const Color(0xfff3f4f9),
      borderRadius: BorderRadius.circular(12.w),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 48.w,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: child,
          ),
        ),
      ),
    );
  }
}

final android = TerminalTheme(
  cursor: 0XAAAEAFAD,
  selection: 0XFFFFFF40,
  foreground: Colors.white.value,
  background: 0XFF000000,
  black: 0XFF000000,
  red: 0XFFCD3131,
  green: 0XFF0DBC79,
  yellow: 0XFFE5E510,
  blue: 0XFF2472C8,
  magenta: 0XFFBC3FBC,
  cyan: 0XFF11A8CD,
  white: 0XFFE5E5E5,
  brightBlack: 0XFF666666,
  brightRed: 0XFFF14C4C,
  brightGreen: 0XFF23D18B,
  brightYellow: 0XFFF5F543,
  brightBlue: 0XFF3B8EEA,
  brightMagenta: 0XFFD670D6,
  brightCyan: 0XFF29B8DB,
  brightWhite: 0XFFFFFFFF,
  searchHitBackground: 0XFFFFFF2B,
  searchHitBackgroundCurrent: 0XFF31FF26,
  searchHitForeground: 0XFF000000,
);

const theme = TerminalTheme(
  cursor: 0XAAAEAFAD,
  selection: 0XFFFFFF40,
  foreground: 0XFF000000,
  background: 0XFF000000,
  black: 0XFF000000,
  red: 0XFFCD3131,
  green: 0XFF0DBC79,
  yellow: 0XFFE5E510,
  blue: 0XFF2472C8,
  magenta: 0XFFBC3FBC,
  cyan: 0XFF11A8CD,
  white: 0XFFE5E5E5,
  brightBlack: 0XFF666666,
  brightRed: 0XFFF14C4C,
  brightGreen: 0XFF23D18B,
  brightYellow: 0XFFF5F543,
  brightBlue: 0XFF3B8EEA,
  brightMagenta: 0XFFD670D6,
  brightCyan: 0XFF29B8DB,
  brightWhite: 0XFFFFFFFF,
  searchHitBackground: 0XFFFFFF2B,
  searchHitBackgroundCurrent: 0XFF31FF26,
  searchHitForeground: 0XFF000000,
);
