// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:yaml/yaml.dart';

/// User-provided settings for invoking an executable.
class ExecutableSettings {
  /// Additional arguments to pass to the executable.
  final List<String> arguments;

  /// The path to the executable on Linux.
  ///
  /// This may be an absolute path or a basename, in which case it will be
  /// looked up on the system path. It may not be relative.
  final String _linuxExecutable;

  /// The path to the executable on Mac OS.
  ///
  /// This may be an absolute path or a basename, in which case it will be
  /// looked up on the system path. It may not be relative.
  final String _macOSExecutable;

  /// The path to the executable on Windows.
  ///
  /// This may be an absolute path; a basename, in which case it will be looked
  /// up on the system path; or a relative path, in which case it will be looked
  /// up relative to the paths in the `LOCALAPPDATA`, `PROGRAMFILES`, and
  /// `PROGRAMFILES(X64)` environment variables.
  final String _windowsExecutable;

  /// The path to the executable for the current operating system.
  String get executable {
    if (Platform.isMacOS) return _macOSExecutable;
    if (!Platform.isWindows) return _linuxExecutable;
    if (p.isAbsolute(_windowsExecutable)) return _windowsExecutable;
    if (p.basename(_windowsExecutable) == _windowsExecutable) {
      return _windowsExecutable;
    }

    var prefixes = [
      Platform.environment['LOCALAPPDATA'],
      Platform.environment['PROGRAMFILES'],
      Platform.environment['PROGRAMFILES(X86)']
    ];

    for (var prefix in prefixes) {
      if (prefix == null) continue;

      var path = p.join(prefix, _windowsExecutable);
      if (new File(path).existsSync()) return path;
    }

    // If we can't find a path that works, return one that doesn't. This will
    // cause an "executable not found" error to surface.
    return p.join(
        prefixes.firstWhere((prefix) => prefix != null, orElse: () => '.'),
        _windowsExecutable);
  }

  /// Parses settings from a user-provided YAML mapping.
  factory ExecutableSettings.parse(YamlMap settings) {
    String linuxExecutable;
    String macOSExecutable;
    String windowsExecutable;
    var executableNode = settings.nodes["executable"];
    if (executableNode != null) {
      if (executableNode.value is String) {
        // Don't check this on Windows because people may want to set relative
        // paths in their global config.
        if (!Platform.isWindows) _assertNotRelative(executableNode);

        linuxExecutable = executableNode.value;
        macOSExecutable = executableNode.value;
        windowsExecutable = executableNode.value;
      } else if (executableNode is YamlMap) {
        linuxExecutable = _getExecutable(executableNode.nodes["linux"]);
        macOSExecutable = _getExecutable(executableNode.nodes["mac_os"]);
        windowsExecutable = _getExecutable(executableNode.nodes["windows"],
            allowRelative: true);
      } else {
        throw new SourceSpanFormatException(
            "Must be a map or a string.", executableNode.span);
      }
    }

    // TODO(nweiz): Parse arguments once io#23 is released.
    return new ExecutableSettings(
        linuxExecutable: linuxExecutable,
        macOSExecutable: macOSExecutable,
        windowsExecutable: windowsExecutable);
  }

  /// Asserts that [executableNode] is a string or `null` and returns it.
  ///
  /// If [allowRelative] is `false` (the default), asserts that the value isn't
  /// a relative path.
  static String _getExecutable(YamlNode executableNode,
      {bool allowRelative: false}) {
    if (executableNode == null || executableNode.value == null) return null;
    if (executableNode.value is! String) {
      throw new SourceSpanFormatException(
          "Must be a string.", executableNode.span);
    }
    if (!allowRelative) _assertNotRelative(executableNode);
    return executableNode.value;
  }

  /// Throws a [SourceSpanFormatException] if [executableNode]'s value is a
  /// relative POSIX path that's not just a plain basename.
  ///
  /// We loop up basenames on the PATH and we can resolve absolute paths, but we
  /// have no way of interpreting relative paths.
  static void _assertNotRelative(YamlScalar executableNode) {
    var executable = executableNode.value as String;
    if (!p.posix.isRelative(executable)) return;
    if (p.posix.basename(executable) == executable) return;

    throw new SourceSpanFormatException(
        "Linux and Mac OS executables may not be relative paths.",
        executableNode.span);
  }

  ExecutableSettings(
      {Iterable<String> arguments,
      String linuxExecutable,
      String macOSExecutable,
      String windowsExecutable})
      : arguments =
            arguments == null ? const [] : new List.unmodifiable(arguments),
        _linuxExecutable = linuxExecutable,
        _macOSExecutable = macOSExecutable,
        _windowsExecutable = windowsExecutable;

  /// Merges [this] with [other], with [other]'s settings taking priority.
  ExecutableSettings merge(ExecutableSettings other) => new ExecutableSettings(
      arguments: arguments.toList()..addAll(other.arguments),
      linuxExecutable: other._linuxExecutable ?? _linuxExecutable,
      macOSExecutable: other._macOSExecutable ?? _macOSExecutable,
      windowsExecutable: other._windowsExecutable ?? _windowsExecutable);
}
