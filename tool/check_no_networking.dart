/// #67: CLAUDE.md requires the app to work fully offline. Two checks:
///
/// 1. Every package this project's dependency tree currently resolves to
///    (`pubspec.lock`'s `packages:` section — direct and transitive alike)
///    must be on [allowedPackages]. Adding a dependency is already a
///    reviewed decision (CLAUDE.md: "ask before adding a dependency");
///    this makes an *unreviewed* one — a new transitive dependency quietly
///    arriving on someone else's version bump — fail CI loudly instead of
///    shipping unnoticed. See the comments inside [allowedPackages] for
///    the handful of entries that look like they carry networking code
///    and why they never run on this app's actual targets (iOS/Android —
///    this project has never shipped to Flutter Web).
/// 2. `lib/` itself may not import a known networking package, or call
///    `dart:io`'s own socket/HTTP primitives directly — see
///    [_bannedImportPrefixes]/[_bannedApiUsage]. `dart:io` as a whole
///    stays allowed (real, non-networking uses: the database file,
///    backups, path resolution), so this is a narrower net than
///    `check_layering.dart`'s domain-wide ban.
///
/// Run: `dart run tool/check_no_networking.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import 'dart_source.dart';

/// Every package this project's resolved dependency tree may name.
/// Alphabetical within each "why it's here" group, so a reviewer can tell
/// an ordinary addition from a networking-capable one at a glance.
const Set<String> allowedPackages = {
  // ---- This app's own direct runtime dependencies (pubspec.yaml
  // "dependencies:").
  'csv',
  'drift',
  'file_picker',
  'fl_chart',
  'flutter',
  'flutter_riverpod',
  'freezed_annotation',
  'json_annotation',
  'package_info_plus',
  'path_provider',
  'pdf',
  'shared_preferences',
  'sqlite3_flutter_libs',
  'yaml',

  // ---- Direct dev-only dependencies (pubspec.yaml "dev_dependencies:")
  // — codegen and the test runner. Never bundled into a release build.
  'build_runner',
  'drift_dev',
  'flutter_lints',
  'freezed',
  'json_schema',
  'json_serializable',
  'path',
  'sqlite3',

  // ---- Ordinary transitive support packages — collections, path
  // handling, code-generation plumbing, platform channels for the
  // plugins above. None of these opens a socket.
  '_fe_analyzer_shared',
  'analyzer',
  'args',
  'async',
  'boolean_selector',
  'build',
  'build_config',
  'built_collection',
  'built_value',
  'characters',
  'charcode',
  'checked_yaml',
  'cli_config',
  'cli_util',
  'clock',
  'code_assets',
  'collection',
  'convert',
  'crypto',
  'dart_style',
  'equatable',
  'fake_async',
  'ffi',
  'ffi_leak_tracker',
  'file',
  'fixnum',
  'flutter_web_plugins',
  'glob',
  'graphs',
  'hooks',
  'io',
  'jni',
  'jni_flutter',
  'jni_util',
  'leak_tracker',
  'leak_tracker_flutter_testing',
  'leak_tracker_testing',
  'lints',
  'listen',
  'logging',
  'matcher',
  'material_color_utilities',
  'meta',
  'mime',
  'native_toolchain_c',
  'objective_c',
  'package_config',
  'package_info_plus_platform_interface',
  'path_provider_android',
  'path_provider_foundation',
  'path_provider_linux',
  'path_provider_platform_interface',
  'path_provider_windows',
  'platform',
  'plugin_platform_interface',
  'pool',
  'pub_semver',
  'pubspec_parse',
  'quiver',
  'recase',
  'record_use',
  'rfc_6901',
  'riverpod',
  'shared_preferences_android',
  'shared_preferences_foundation',
  'shared_preferences_linux',
  'shared_preferences_platform_interface',
  'shared_preferences_web',
  'shared_preferences_windows',
  'sky_engine',
  'source_gen',
  'source_helper',
  'source_map_stack_trace',
  'source_maps',
  'source_span',
  'sqlparser',
  'stack_trace',
  'state_notifier',
  'stream_channel',
  'stream_transform',
  'string_scanner',
  'term_glyph',
  'typed_data',
  'uri',
  'uuid',
  'vector_math',
  'watcher',
  'web',
  'win32',
  'xdg_directories',

  // ---- file_picker (#72's import flow) and its own transitive tree —
  // every one of these opens a native document/file picker or supports
  // one; none opens a socket. `dbus` is Linux desktop-portal IPC (the
  // GTK/KDE file-open dialog), not network I/O, and irrelevant on this
  // app's actual targets regardless (iOS/Android). `xml`/`petitparser`
  // back `file_picker`'s Windows/macOS metadata parsing.
  'android_file_picker',
  'cross_file',
  'dbus',
  'file_picker_darwin',
  'file_picker_linux',
  'file_picker_platform_interface',
  'file_picker_web',
  'petitparser',
  'windows_file_picker',
  'xml',

  // ---- pdf (#76's AMC1 FCL.050 layout) and its own transitive tree — pure
  // document/image generation, no I/O of its own. `image`/`archive` decode
  // and encode bitmaps (`archive` is `image`'s own zip/deflate support for
  // formats like PNG); `path_parsing` parses SVG path data for vector
  // drawing; `posix`, `qr` and `barcode` are the pdf package's own
  // dependencies for POSIX font-directory lookups, QR codes and barcode
  // generation; `bidi` supports right-to-left text shaping. None of it is
  // reachable on this app's targets (iOS/Android) or used by this codebase.
  'archive',
  'barcode',
  'bidi',
  'image',
  'path_parsing',
  'posix',
  'qr',

  // ---- Genuinely networking-capable packages, present but dead code on
  // this app's targets.
  //
  // `http`: pulled in transitively by `package_info_plus`, whose *own*
  // `http` import lives only in `package_info_plus_web.dart` (fetches
  // the web app's own same-origin manifest.json — never a third-party
  // call, and never reached regardless: this app has never targeted
  // Flutter Web). Every other platform implementation
  // (`package_info_plus_windows.dart`, the Android/iOS native channel)
  // uses `dart:io` file APIs or a platform channel, not `http`.
  'http',
  // `flutter_test` and everything below it is the Dart/Flutter test and
  // build-tooling stack. `flutter_riverpod` uncommonly declares
  // `flutter_test` as a *regular* (non-dev) dependency — it ships a
  // testing helper from its main library — which drags in the local
  // test-runner's own HTTP/WebSocket server (`shelf*`, `web_socket*`,
  // `http_multi_server`, `vm_service`, `coverage`) as a side effect.
  // None of it is reachable from this app's own code, which never
  // imports `flutter_test` outside `test/` — and `test/` never ships.
  'build_daemon',
  'coverage',
  'flutter_test',
  'frontend_server_client',
  'http_multi_server',
  'http_parser',
  'node_preamble',
  'shelf',
  'shelf_packages_handler',
  'shelf_static',
  'shelf_web_socket',
  'test',
  'test_api',
  'test_core',
  'vm_service',
  'web_socket',
  'web_socket_channel',
  'webkit_inspection_protocol',
};

/// Import/export URI prefixes `lib/` may not depend on — unlike
/// `check_layering.dart`'s domain-wide ban, `dart:io` itself stays off
/// this list: the database file, backups and path resolution are real,
/// non-networking uses of it elsewhere in `lib/`.
const List<String> _bannedImportPrefixes = <String>[
  'package:http/',
  'package:dio/',
  'package:cupertino_http/',
  'package:web_socket_channel/',
  'package:firebase_',
  'package:sentry',
  'package:crashlytics',
];

/// `dart:io`'s own network primitives, called directly rather than via a
/// banned package import — the gap [_bannedImportPrefixes] alone can't
/// close, since `dart:io` is otherwise allowed.
final RegExp _bannedApiUsage = RegExp(
  r'\b(HttpClient|WebSocket|RawSocket|RawDatagramSocket)\s*\.?\s*connect\s*\('
  r'|\bHttpClient\s*\('
  r'|\bInternetAddress\s*\.\s*lookup\s*\(',
);

const String _lockfilePath = 'pubspec.lock';
const String _sourceTarget = 'lib';

/// Parses `pubspec.lock`'s `packages:` map, returning every package name
/// it resolves — the ground truth of what `pub get` actually fetched, not
/// just what `pubspec.yaml` declares directly.
List<String> resolvedPackageNames(String lockfileContent) {
  final doc = loadYaml(lockfileContent);
  if (doc is! YamlMap) return const [];
  final packages = doc['packages'];
  if (packages is! YamlMap) return const [];
  return packages.keys.cast<String>().toList();
}

/// A banned import, or a direct call to a `dart:io` network primitive,
/// found in a `lib/` file.
class SourceViolation {
  const SourceViolation({
    required this.filePath,
    required this.line,
    required this.detail,
  });

  final String filePath;
  final int line;
  final String detail;

  @override
  String toString() => '$filePath:$line  $detail';
}

List<SourceViolation> findSourceViolations(String filePath, String source) {
  filePath = filePath.replaceAll(r'\', '/');
  final stripped = stripComments(source);
  final violations = <SourceViolation>[];

  for (final lineMatch
      in const LineSplitter().convert(stripped).asMap().entries) {
    final lineNumber = lineMatch.key + 1;
    final line = lineMatch.value;
    if (line.trimLeft().startsWith('import') ||
        line.trimLeft().startsWith('export')) {
      for (final prefix in _bannedImportPrefixes) {
        if (line.contains(prefix)) {
          violations.add(
            SourceViolation(
              filePath: filePath,
              line: lineNumber,
              detail: 'imports a banned networking package ($prefix)',
            ),
          );
        }
      }
    }
  }

  for (final match in _bannedApiUsage.allMatches(stripped)) {
    final lineNumber =
        '\n'.allMatches(stripped.substring(0, match.start)).length + 1;
    violations.add(
      SourceViolation(
        filePath: filePath,
        line: lineNumber,
        detail: 'calls a network primitive directly (${match.group(0)})',
      ),
    );
  }

  return violations;
}

void main() {
  var failed = false;

  final lockfile = File(_lockfilePath);
  if (!lockfile.existsSync()) {
    stderr.writeln(
      'check_no_networking: $_lockfilePath not found — run `flutter pub get` first.',
    );
    exit(1);
  }

  final resolved = resolvedPackageNames(lockfile.readAsStringSync());
  final unexpected =
      resolved.where((p) => !allowedPackages.contains(p)).toList()..sort();

  if (unexpected.isEmpty) {
    stdout.writeln(
      'check_no_networking: every resolved dependency (${resolved.length}) is on the allowlist.',
    );
  } else {
    failed = true;
    stderr.writeln(
      'check_no_networking: ${unexpected.length} dependency/ies not on the allowlist:',
    );
    for (final name in unexpected) {
      stderr.writeln('  $name');
    }
    stderr.writeln('');
    stderr.writeln(
      'CLAUDE.md: no cloud backend, account system or analytics without '
      "being asked, and the app must work fully offline (#67). If this is "
      "a deliberate addition, confirm it performs no network I/O on this "
      "app's shipped targets (iOS/Android) and add it to allowedPackages "
      'in tool/check_no_networking.dart with a comment saying why.',
    );
  }

  final directory = Directory(_sourceTarget);
  if (directory.existsSync()) {
    final sourceViolations = <SourceViolation>[];
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('.freezed.dart') ||
          entity.path.endsWith('.g.dart')) {
        continue;
      }
      sourceViolations.addAll(
        findSourceViolations(entity.path, entity.readAsStringSync()),
      );
    }

    if (sourceViolations.isEmpty) {
      stdout.writeln('check_no_networking: $_sourceTarget is clean.');
    } else {
      failed = true;
      stderr.writeln(
        'check_no_networking: ${sourceViolations.length} source violation(s):',
      );
      for (final violation in sourceViolations) {
        stderr.writeln('  $violation');
      }
    }
  }

  exit(failed ? 1 : 0);
}
