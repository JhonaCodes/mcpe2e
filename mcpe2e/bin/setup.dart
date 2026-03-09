// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

// ── ANSI ──────────────────────────────────────────────────────────────────────
const _r   = '\x1B[0m';
const _b   = '\x1B[1m';
const _dim = '\x1B[2m';
const _g   = '\x1B[32m';
const _red = '\x1B[31m';
const _c   = '\x1B[36m';
const _gr  = '\x1B[90m';

// ── Config ────────────────────────────────────────────────────────────────────
const _repo    = 'JhonaCodes/mcpe2e';
const _version = '1.0.8';

String get _installDir {
  if (Platform.isWindows) {
    return '${Platform.environment['LOCALAPPDATA']}\\mcpe2e';
  }
  return '${Platform.environment['HOME']}/.local/bin';
}

String get _binaryName => Platform.isWindows ? 'mcpe2e_server.exe' : 'mcpe2e_server';
String get _binaryPath => '$_installDir${Platform.pathSeparator}$_binaryName';

// ── Entry point ───────────────────────────────────────────────────────────────

Future<void> main() async {
  _printHeader();

  final asset = _detectAsset();
  if (asset == null) {
    final os   = Platform.operatingSystem;
    final arch = _arch;
    print('$_red  ✗ No prebuilt binary for $os/$arch.$_r');
    if (os == 'macos' && arch == 'x86_64') {
      print('    Intel Macs are not supported yet. Build from source:');
    } else {
      print('    Build from source:');
    }
    print('    cd mcpe2e_server');
    print('    dart compile exe bin/mcp_server.dart -o ~/.local/bin/mcpe2e_server');
    exit(1);
  }

  await _cleanOldInstall();
  final ok = await _download(asset);
  if (!ok) exit(1);

  await _openSetupTui();
}

// ── Platform detection ────────────────────────────────────────────────────────

String? _detectAsset() {
  final os   = Platform.operatingSystem;
  final arch = _arch;
  if (os == 'macos'   && arch == 'arm64')  return 'mcpe2e_server-macos-arm64';
  if (os == 'linux'   && arch == 'x86_64') return 'mcpe2e_server-linux-x86_64';
  if (os == 'windows')                      return 'mcpe2e_server.exe';
  return null;
}

String get _arch {
  try {
    final r = Process.runSync('uname', ['-m']);
    return (r.stdout as String).trim();
  } catch (_) {
    return Platform.environment['PROCESSOR_ARCHITECTURE']?.toLowerCase() == 'amd64'
        ? 'x86_64'
        : 'unknown';
  }
}

// ── Clean old install ─────────────────────────────────────────────────────────

Future<void> _cleanOldInstall() async {
  print('  ${_dim}[ 1/2 ] Cleaning previous install...$_r');

  final f = File(_binaryPath);
  if (f.existsSync()) {
    f.deleteSync();
    print('  ${_gr}  removed $_binaryPath$_r');
  }

  // Remove from Claude Code if registered
  try {
    final result = Process.runSync('claude', ['mcp', 'remove', 'mcpe2e']);
    if (result.exitCode == 0) print('  ${_gr}  removed from Claude Code$_r');
  } catch (_) {}
}

// ── Download binary ───────────────────────────────────────────────────────────

Future<bool> _download(String asset) async {
  print('');
  print('  ${_dim}[ 2/2 ] Installing binary...$_r');

  // Fetch latest tag
  String tag;
  try {
    final client = HttpClient();
    final req    = await client.getUrl(
      Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
    );
    req.headers.set('User-Agent', 'mcpe2e-setup/$_version');
    req.headers.set('Accept', 'application/vnd.github+json');
    final res  = await req.close();
    final body = await res.transform(utf8.decoder).join();
    client.close();

    if (res.statusCode != 200) {
      final decoded = jsonDecode(body) as Map;
      final msg = decoded['message'] ?? 'HTTP ${res.statusCode}';
      print('$_red  ✗ GitHub API error: $msg$_r');
      if (msg.toString().contains('rate limit')) {
        print('    Too many requests from this IP. Wait a few minutes and try again.');
      }
      return false;
    }
    final decoded = jsonDecode(body) as Map;
    final rawTag  = decoded['tag_name'];
    if (rawTag == null) {
      print('$_red  ✗ No GitHub release found yet.$_r');
      print('    $_dim https://github.com/$_repo/actions$_r');
      return false;
    }
    tag = rawTag as String;
  } catch (e) {
    print('$_red  ✗ Could not fetch latest release: $e$_r');
    return false;
  }

  // Download binary
  final url = 'https://github.com/$_repo/releases/download/$tag/$asset';
  print('  ${_dim}Downloading $asset ($tag)...$_r');

  try {
    Directory(_installDir).createSync(recursive: true);
    final client = HttpClient();
    final req    = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'mcpe2e-setup/$_version');
    final res    = await req.close();

    if (res.statusCode != 200) {
      print('$_red  ✗ Download failed: HTTP ${res.statusCode}$_r');
      client.close();
      return false;
    }

    final file = File(_binaryPath).openWrite();
    await res.pipe(file);
    client.close();

    if (!Platform.isWindows) {
      Process.runSync('chmod', ['+x', _binaryPath]);
    }

    print('  ${_g}✓ $_binaryPath$_r');
    return true;
  } catch (e) {
    print('$_red  ✗ Download error: $e$_r');
    return false;
  }
}

// ── Launch interactive setup TUI ──────────────────────────────────────────────

Future<void> _openSetupTui() async {
  print('');
  stdout.writeln('  Opening agent registration...');
  sleep(const Duration(milliseconds: 500));

  final process = await Process.start(
    _binaryPath,
    ['setup'],
    mode: ProcessStartMode.inheritStdio,
  );

  exit(await process.exitCode);
}

// ── UI ────────────────────────────────────────────────────────────────────────

void _printHeader() {
  const w   = 54;
  const pad = '  ';
  stdout.writeln('');
  stdout.writeln('$pad$_b$_c┌${'─' * w}┐$_r');
  stdout.writeln('$pad$_b$_c│${_center('mcpe2e setup', w)}│$_r');
  stdout.writeln('$pad$_b$_c│${_center('AI Agent E2E Bridge for Flutter', w)}│$_r');
  stdout.writeln('$pad$_b$_c└${'─' * w}┘$_r');
  stdout.writeln('');
}

String _center(String text, int width) {
  final pad = ((width - text.length) / 2).floor();
  return text.padLeft(text.length + pad).padRight(width);
}
