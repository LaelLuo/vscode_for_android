// code-server版本号
import 'package:global_repository/global_repository.dart';

String version = '4.5.1';
// prootDistro 路径
String prootDistroPath = '${RuntimeEnvir.usrPath}/var/lib/proot-distro';
// ubuntu 路径
String ubuntuPath = '$prootDistroPath/installed-rootfs/ubuntu';
String lockFile = '${RuntimeEnvir.dataPath}/cache/init_lock';
// 清华源
String source = '''
# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-backports main restricted universe multiverse
deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-security main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-security main restricted universe multiverse

# 预发布软件源，不建议启用
# deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse
# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ jammy-proposed main restricted universe multiverse
''';

String colorEcho = '''
colorEcho(){
  echo -e "\\033[31m\$@\\033[0m"
}
''';

// String installVsCodeScriptWithoutFullLinux = '''
// $colorEcho
// install_vs_code(){
//   colorEcho - 安装依赖
//   apt-get install -y libllvm
//   apt-get install -y clang
//   apt-get install -y nodejs
//   apt-get install -y python
//   apt-get install -y yarn
//   colorEcho - 解压 Vs Code Arm64
//   cd ~
//   unzip code-server-3.11.1-linux-arm64.zip
//   colorEcho - 执行 yarn install
//   cd code-server-3.11.1-linux-arm64
//   yarn config set registry https://registry.npm.taobao.org --global
//   yarn config set disturl https://npm.taobao.org/dist --global
//   npm config set registry https://registry.npm.taobao.org
//   yarn install
// }
// ''';
/// 安装ubuntu的shell
String installUbuntu = '''
install_ubuntu(){
  cd ~
  colorEcho - 安装Ubuntu Linux
  unzip proot-distro.zip >/dev/null
  #cd ~/proot-distro
  bash ./install.sh
  apt-get install -y proot
  proot-distro install ubuntu
  echo '$source' > $ubuntuPath/etc/apt/sources.list
  echo 'export PATH=/home/code-server-$version-linux-arm64/bin:\$PATH' >> $ubuntuPath/root/.bashrc
}
''';

String get serverPath => '$ubuntuPath/home/code-server-$version-linux-arm64.tar.gz';

/// 安装code-server的脚本
String installVsCodeScript = '''
$colorEcho
install_vs_code(){
  if [ ! -d "$ubuntuPath/home/code-server-$version-linux-arm64" ];then
    cd $ubuntuPath/home
    server_path="$serverPath"
    if [ ! -f "\$server_path" ];then
      colorEcho - 下载 Vs Code Arm64
      dart_dio \\
      https://github.com/coder/code-server/releases/download/v$version/code-server-$version-linux-arm64.tar.gz \\
      $serverPath
    fi
    colorEcho - 解压 Vs Code Arm64
    proot-distro login ubuntu -- tar zxfh \$server_path -C /home
    cd code-server-$version-linux-arm64
  fi
}
''';

// TODO 加上端口的kill
/// 启动 vs code 的shell
String startVsCodeScript = '''
$installVsCodeScript
start_vs_code(){
  install_vs_code
  mkdir -p $ubuntuPath/root/.config/code-server 2>/dev/null
  echo '$source' > $ubuntuPath/etc/apt/sources.list
  echo '
  bind-addr: 0.0.0.0:10000
  auth: none
  password: none
  cert: false
  ' > $ubuntuPath/root/.config/code-server/config.yaml
  echo -e "\\033[31m- 启动中..\\033[0m"
  proot-distro login ubuntu -- /home/code-server-$version-linux-arm64/bin/code-server
}
''';

String getRedLog(String data) {
  return '\x1b[31m$data\x1b[0m';
}

/// 初始化类Linux环境的shell
String initShell = '''
$installUbuntu
$startVsCodeScript
function initApp(){
  cd ${RuntimeEnvir.usrPath}/
  colorEcho - 准备符号链接...
  for line in `cat SYMLINKS.txt`
  do
    OLD_IFS="\$IFS"
    IFS="←"
    arr=(\$line)
    IFS="\$OLD_IFS"
    ln -s \${arr[0]} \${arr[3]}
  done
  rm -rf SYMLINKS.txt
  TMPDIR=${RuntimeEnvir.tmpPath}
  filename=bootstrap
  rm -rf "\$TMPDIR/\$filename*"
  rm -rf "\$TMPDIR/*"
  chmod -R 0777 ${RuntimeEnvir.binPath}/*
  chmod -R 0777 ${RuntimeEnvir.usrPath}/lib/* 2>/dev/null
  chmod -R 0777 ${RuntimeEnvir.usrPath}/libexec/* 2>/dev/null
  apt update
  rm -rf $lockFile
  export LD_PRELOAD=${RuntimeEnvir.usrPath}/lib/libtermux-exec.so
  install_ubuntu
  start_vs_code
  bash
}
''';
