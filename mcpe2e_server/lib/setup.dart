// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'version.dart';

// ── ANSI ──────────────────────────────────────────────────────────────────────
const _r   = '\x1B[0m';
const _b   = '\x1B[1m';
const _dim = '\x1B[2m';
const _g   = '\x1B[32m';
const _red = '\x1B[31m';
const _y   = '\x1B[33m';
const _c   = '\x1B[36m';
const _gr  = '\x1B[90m';

// ── Agent model ───────────────────────────────────────────────────────────────

enum _Format { claudeCode, json, toml }

class _Agent {
  final String id;
  final String name;
  final String configPath;
  final _Format format;
  const _Agent(this.id, this.name, this.configPath, this.format);
}

// ── Setup controller ──────────────────────────────────────────────────────────

class _Setup {
  final String binaryPath;
  final String bridgeUrl;

  _Setup(this.binaryPath, this.bridgeUrl);

  static String get _home => Platform.environment['HOME'] ?? '';

  static String get _claudeDesktop {
    if (Platform.isMacOS) {
      return '$_home/Library/Application Support/Claude/claude_desktop_config.json';
    }
    return '$_home/.config/claude/claude_desktop_config.json';
  }

  List<_Agent> get agents => [
        _Agent('claude_code',    'Claude Code',         '$_home/.claude.json',               _Format.claudeCode),
        _Agent('claude_desktop', 'Claude Desktop',      _claudeDesktop,                      _Format.json),
        _Agent('codex',          'Codex CLI (OpenAI)',  '$_home/.codex/config.toml',          _Format.toml),
        _Agent('gemini',         'Gemini CLI (Google)', '$_home/.gemini/settings.json',       _Format.json),
      ];

  // ── Status checks ───────────────────────────────────────────────────────────

  bool installed(_Agent a) => switch (a.id) {
        'claude_code'    => _cmd('claude'),
        'claude_desktop' => File(a.configPath).existsSync() ||
                            Directory(File(a.configPath).parent.path).existsSync(),
        'codex'          => _cmd('codex') || Directory('$_home/.codex').existsSync(),
        'gemini'         => _cmd('gemini') || Directory('$_home/.gemini').existsSync(),
        _                => false,
      };

  bool registered(_Agent a) {
    final f = File(a.configPath);
    if (!f.existsSync()) return false;
    try {
      final content = f.readAsStringSync();
      return switch (a.format) {
        _Format.toml => content.contains('[mcp_servers.mcpe2e]'),
        _            => (jsonDecode(content)?['mcpServers'] as Map?)?.containsKey('mcpe2e') ?? false,
      };
    } catch (_) {
      return false;
    }
  }

  bool _cmd(String name) {
    try {
      return Process.runSync('which', [name]).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ── Enable / Disable ────────────────────────────────────────────────────────

  void enable(_Agent a) => switch (a.format) {
        _Format.claudeCode => _enableClaude(),
        _Format.json       => _patchJson(a.configPath, add: true),
        _Format.toml       => _patchToml(a.configPath, add: true),
      };

  void disable(_Agent a) => switch (a.format) {
        _Format.claudeCode => _disableClaude(),
        _Format.json       => _patchJson(a.configPath, add: false),
        _Format.toml       => _patchToml(a.configPath, add: false),
      };

  void _enableClaude() {
    try { Process.runSync('claude', ['mcp', 'remove', 'mcpe2e']); } catch (_) {}
    Process.runSync('claude', [
      'mcp', 'add', 'mcpe2e', '-e', 'TESTBRIDGE_URL=$bridgeUrl', '--', binaryPath,
    ]);
  }

  void _disableClaude() {
    try { Process.runSync('claude', ['mcp', 'remove', 'mcpe2e']); } catch (_) {}
  }

  void _patchJson(String path, {required bool add}) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    Map<String, dynamic> cfg = {};
    if (file.existsSync()) {
      try { cfg = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>; } catch (_) {}
    }
    final servers = (cfg['mcpServers'] as Map<String, dynamic>?) ?? {};
    if (add) {
      servers['mcpe2e'] = {'command': binaryPath, 'args': <String>[], 'env': {'TESTBRIDGE_URL': bridgeUrl}};
    } else {
      servers.remove('mcpe2e');
    }
    cfg['mcpServers'] = servers;
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cfg) + '\n');
  }

  void _patchToml(String path, {required bool add}) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    var content = file.existsSync() ? file.readAsStringSync() : '';
    content = content
        .replaceAll(RegExp(r'\[mcp_servers\.mcpe2e\][^\[]*', dotAll: true), '')
        .trimRight();
    if (add) {
      content += '\n\n[mcp_servers.mcpe2e]\ncommand = "$binaryPath"\nenv = { TESTBRIDGE_URL = "$bridgeUrl" }\n';
    } else {
      content += '\n';
    }
    file.writeAsStringSync(content);
  }
}

// ── UI ────────────────────────────────────────────────────────────────────────

Future<void> runSetup() async {
  final binary    = Platform.resolvedExecutable;
  final bridgeUrl = Platform.environment['TESTBRIDGE_URL'] ?? 'http://localhost:7778';
  final setup     = _Setup(binary, bridgeUrl);

  while (true) {
    _render(setup);
    stdout.write('  $_b>$_r Enter choice: ');

    final input = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    if (input == 'q') break;

    if (input == 'a') {
      for (final a in setup.agents) {
        if (setup.installed(a)) setup.enable(a);
      }
      _flash('  ${_g}✓ All available agents enabled.$_r');
      continue;
    }

    if (input == 'n') {
      for (final a in setup.agents) {
        setup.disable(a);
      }
      _flash('  ${_y}○ All agents disabled.$_r');
      continue;
    }

    final idx = int.tryParse(input);
    if (idx != null && idx >= 1 && idx <= setup.agents.length) {
      final a = setup.agents[idx - 1];
      if (!setup.installed(a)) {
        _flash('  ${_red}✗ ${a.name} is not installed on this machine.$_r');
        continue;
      }
      if (setup.registered(a)) {
        setup.disable(a);
        _flash('  ${_y}○ ${a.name} — disabled.$_r');
      } else {
        setup.enable(a);
        _flash('  ${_g}✓ ${a.name} — enabled.$_r');
      }
    }
  }

  _clear();
  stdout.writeln('  ${_c}Done.$_r\n');
}

void _render(_Setup setup) {
  _clear();

  const w = 56;
  const pad = '  ';

  // Header
  stdout.writeln('$pad$_b$_c┌${'─' * w}┐$_r');
  stdout.writeln('$pad$_b$_c│${_center('mcpe2e setup', w)}│$_r');
  stdout.writeln('$pad$_b$_c│${_center('AI Agent MCP Registration Manager', w)}│$_r');
  stdout.writeln('$pad$_b$_c└${'─' * w}┘$_r');
  stdout.writeln('');

  // Info
  final binShort = setup.binaryPath.replaceAll(Platform.environment['HOME'] ?? '', '~');
  stdout.writeln('$pad${_dim}binary  : $binShort$_r');
  stdout.writeln('$pad${_dim}bridge  : ${setup.bridgeUrl}$_r');
  stdout.writeln('$pad${_dim}version : v$kServerVersion$_r');
  stdout.writeln('');
  stdout.writeln('$pad$_gr${'─' * w}$_r');
  stdout.writeln('');

  // Agent list
  final agents = setup.agents;
  for (var i = 0; i < agents.length; i++) {
    final a          = agents[i];
    final inst       = setup.installed(a);
    final reg        = inst && setup.registered(a);
    final num        = '$_b[${i + 1}]$_r';
    final namePad    = a.name.padRight(24);
    final cfgShort   = a.configPath.replaceAll(Platform.environment['HOME'] ?? '', '~');

    final dot = reg  ? '${_g}●$_r' :
                inst ? '${_y}○$_r' :
                       '${_red}✗$_r';

    final statusText = reg  ? '${_g}enabled$_r ' :
                       inst ? '${_y}disabled$_r' :
                              '${_red}not found$_r';

    final cfgText = (reg || inst) ? ' $_gr$cfgShort$_r' : '';

    stdout.writeln('$pad $num $_b$namePad$_r $dot $statusText$cfgText');
  }

  stdout.writeln('');
  stdout.writeln('$pad$_gr${'─' * w}$_r');
  stdout.writeln('');
  stdout.writeln('$pad ${_b}[a]$_r Enable all   ${_b}[n]$_r Disable all   ${_b}[q]$_r Quit');
  stdout.writeln('');
}

void _flash(String msg) {
  stdout.writeln(msg);
  sleep(const Duration(milliseconds: 700));
}

void _clear() => stdout.write('\x1B[2J\x1B[H');

String _center(String text, int width) {
  final pad = ((width - text.length) / 2).floor();
  return text.padLeft(text.length + pad).padRight(width);
}
