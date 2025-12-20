#!/usr/bin/env dart
// ignore_for_file: avoid_print

// ignore: dangling_library_doc_comments
/// Migration script for converting old enum converter classes to new helper functions
///
/// This script helps migrate from the old (broken) converter class pattern to the
/// new helper function pattern that actually works.
///
/// Usage:
///   dart run migration_scripts/migrate_enum_converters.dart [--dry-run] [path]
///
/// Options:
///   --dry-run    Show what would be changed without modifying files
///   path         Directory to scan (defaults to lib/)
///
/// Example:
///   dart run migration_scripts/migrate_enum_converters.dart --dry-run
///   dart run migration_scripts/migrate_enum_converters.dart lib/data/models/

import 'dart:io';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final pathArg = args.where((a) => !a.startsWith('--')).firstOrNull;
  final targetPath = pathArg ?? 'lib/';

  print('🔄 Enum Converter Migration Tool');
  print('================================\n');

  if (dryRun) {
    print('🔍 DRY RUN MODE - No files will be modified\n');
  }

  final dir = Directory(targetPath);
  if (!dir.existsSync()) {
    print('❌ Error: Directory "$targetPath" does not exist');
    exit(1);
  }

  print('📂 Scanning: $targetPath\n');

  final dartFiles = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart')) // Skip generated files
      .toList();

  print('📄 Found ${dartFiles.length} Dart files\n');

  var filesModified = 0;
  var convertersFound = 0;
  var fieldsUpdated = 0;

  for (final file in dartFiles) {
    final result = _analyzeAndMigrateFile(file, dryRun);
    if (result.modified) {
      filesModified++;
      convertersFound += result.convertersRemoved;
      fieldsUpdated += result.fieldsUpdated;
    }
  }

  print('\n${'=' * 50}');
  print('📊 Migration Summary');
  print('=' * 50);
  print('Files scanned:        ${dartFiles.length}');
  print('Files modified:       $filesModified');
  print('Converters removed:   $convertersFound');
  print('Fields updated:       $fieldsUpdated');

  if (dryRun) {
    print('\n💡 Run without --dry-run to apply changes');
  } else {
    print('\n✅ Migration complete!');
    print('⚠️  Remember to:');
    print('   1. Run: dart run build_runner build --delete-conflicting-outputs');
    print('   2. Test your app thoroughly');
    print('   3. Review the changes in version control');
  }
}

class MigrationResult {
  final bool modified;
  final int convertersRemoved;
  final int fieldsUpdated;

  MigrationResult({
    required this.modified,
    required this.convertersRemoved,
    required this.fieldsUpdated,
  });
}

MigrationResult _analyzeAndMigrateFile(File file, bool dryRun) {
  final content = file.readAsStringSync();
  var modified = false;
  var convertersRemoved = 0;
  var fieldsUpdated = 0;

  // Check if file contains old converter patterns
  final hasOldConverters = RegExp(
    r'extends\s+(NullableEnumConverter|DefaultEnumConverter|LoggingEnumConverter)',
  ).hasMatch(content);

  if (!hasOldConverters) {
    return MigrationResult(
      modified: false,
      convertersRemoved: 0,
      fieldsUpdated: 0,
    );
  }

  print('🔧 Migrating: ${file.path}');

  var newContent = content;

  // Extract enum and converter information
  final converters = _extractConverters(content);

  for (final converter in converters) {
    print('   • Found ${converter.type} converter: ${converter.className}');
    convertersRemoved++;

    // Generate helper functions
    final helperFunctions = _generateHelperFunctions(converter);

    // Remove the converter class
    newContent = _removeConverterClass(newContent, converter);

    // Add helper functions after the enum definition
    newContent = _addHelperFunctions(newContent, converter, helperFunctions);

    // Update field annotations
    final fieldUpdates = _updateFieldAnnotations(newContent, converter);
    newContent = fieldUpdates.content;
    fieldsUpdated += fieldUpdates.count;
  }

  if (converters.isNotEmpty) {
    modified = true;

    if (!dryRun) {
      file.writeAsStringSync(newContent);
      print('   ✅ Migrated successfully\n');
    } else {
      print('   📝 Would migrate (dry-run)\n');
    }
  }

  return MigrationResult(
    modified: modified,
    convertersRemoved: convertersRemoved,
    fieldsUpdated: fieldsUpdated,
  );
}

class ConverterInfo {
  final String className;
  final String enumName;
  final String type; // 'nullable', 'default', or 'logging'
  final String? defaultValue;
  final String fullText;

  ConverterInfo({
    required this.className,
    required this.enumName,
    required this.type,
    this.defaultValue,
    required this.fullText,
  });
}

List<ConverterInfo> _extractConverters(String content) {
  final converters = <ConverterInfo>[];

  // Pattern to match converter classes
  final converterPattern = RegExp(
    r'class\s+(\w+)\s+extends\s+(NullableEnumConverter|DefaultEnumConverter|LoggingEnumConverter)<(\w+)>\s*{[^}]*}',
    multiLine: true,
    dotAll: true,
  );

  for (final match in converterPattern.allMatches(content)) {
    final className = match.group(1)!;
    final baseClass = match.group(2)!;
    final enumName = match.group(3)!;
    final fullText = match.group(0)!;

    // Determine converter type
    String type;
    String? defaultValue;

    if (baseClass == 'NullableEnumConverter') {
      type = 'nullable';
    } else if (baseClass == 'DefaultEnumConverter') {
      type = 'default';
      // Try to extract default value
      final defaultMatch = RegExp(r'get\s+defaultValue\s*=>\s*(\w+\.\w+);').firstMatch(fullText);
      defaultValue = defaultMatch?.group(1);
    } else {
      type = 'logging';
      final defaultMatch = RegExp(r'get\s+defaultValue\s*=>\s*(\w+\.\w+);').firstMatch(fullText);
      defaultValue = defaultMatch?.group(1);
    }

    converters.add(ConverterInfo(
      className: className,
      enumName: enumName,
      type: type,
      defaultValue: defaultValue,
      fullText: fullText,
    ));
  }

  return converters;
}

String _generateHelperFunctions(ConverterInfo converter) {
  final enumName = converter.enumName;
  final funcBaseName = '_deserialize$enumName';
  final serializeFuncName = '_serialize$enumName';

  final buffer = StringBuffer();

  buffer.writeln('// Helper functions for $enumName');

  if (converter.type == 'nullable') {
    buffer.writeln('$enumName? $funcBaseName(String? value) {');
    buffer.writeln('  return safeEnumFromJson(value, $enumName.values);');
    buffer.writeln('}');
  } else if (converter.type == 'default') {
    final defaultVal = converter.defaultValue ?? '$enumName.values.first';
    buffer.writeln('$enumName $funcBaseName(String? value) {');
    buffer.writeln('  return safeEnumFromJson(');
    buffer.writeln('    value,');
    buffer.writeln('    $enumName.values,');
    buffer.writeln('    defaultValue: $defaultVal,');
    buffer.writeln('  )!;');
    buffer.writeln('}');
  } else {
    // logging
    final defaultVal = converter.defaultValue ?? '$enumName.values.first';
    buffer.writeln('$enumName $funcBaseName(String? value) {');
    buffer.writeln('  return safeEnumFromJson(');
    buffer.writeln('    value,');
    buffer.writeln('    $enumName.values,');
    buffer.writeln('    defaultValue: $defaultVal,');
    buffer.writeln('    onUnknownValue: (v) {');
    buffer.writeln('      logw(\'Unknown $enumName: \$v, defaulting to $defaultVal\');');
    buffer.writeln('    },');
    buffer.writeln('  )!;');
    buffer.writeln('}');
  }

  buffer.writeln();
  buffer.writeln('String? $serializeFuncName($enumName? value) {');
  buffer.writeln('  return safeEnumToJson(value);');
  buffer.writeln('}');

  return buffer.toString();
}

String _removeConverterClass(String content, ConverterInfo converter) {
  // Remove the entire converter class
  return content.replaceAll(converter.fullText, '');
}

String _addHelperFunctions(
  String content,
  ConverterInfo converter,
  String helperFunctions,
) {
  // Find the enum definition
  final enumPattern = RegExp(
    r'enum\s+' + converter.enumName + r'\s*{[^}]*}',
    multiLine: true,
  );

  final enumMatch = enumPattern.firstMatch(content);
  if (enumMatch == null) {
    print('   ⚠️  Warning: Could not find enum ${converter.enumName}');
    return content;
  }

  // Insert helper functions after the enum
  final enumEnd = enumMatch.end;
  return '${content.substring(0, enumEnd)}\n\n$helperFunctions\n${content.substring(enumEnd)}';
}

class UpdateResult {
  final String content;
  final int count;

  UpdateResult(this.content, this.count);
}

UpdateResult _updateFieldAnnotations(String content, ConverterInfo converter) {
  var newContent = content;
  var count = 0;

  final funcBaseName = '_deserialize${converter.enumName}';
  final serializeFuncName = '_serialize${converter.enumName}';

  // Pattern to match field annotations
  // Matches: @ConverterClassName() or @ConverterClassName
  final annotationPattern = RegExp(
    r'@' + converter.className + r'\(\)\s*\n\s*final\s+' + converter.enumName + r'\??',
    multiLine: true,
  );

  final matches = annotationPattern.allMatches(content).toList();

  // Replace from end to start to maintain indices
  for (final match in matches.reversed) {
    final oldAnnotation = match.group(0)!;
    final isNullable = oldAnnotation.contains('${converter.enumName}?');

    final newAnnotation =
        '@JsonKey(fromJson: $funcBaseName, toJson: $serializeFuncName)\n  final ${converter.enumName}${isNullable ? '?' : ''}';

    newContent = newContent.replaceRange(
      match.start,
      match.end,
      newAnnotation,
    );
    count++;
  }

  // Also handle annotations without parentheses
  final annotationPattern2 = RegExp(
    r'@' + converter.className + r'\s+\n\s*final\s+' + converter.enumName + r'\??',
    multiLine: true,
  );

  final matches2 = annotationPattern2.allMatches(newContent).toList();

  for (final match in matches2.reversed) {
    final oldAnnotation = match.group(0)!;
    final isNullable = oldAnnotation.contains('${converter.enumName}?');

    final newAnnotation =
        '@JsonKey(fromJson: $funcBaseName, toJson: $serializeFuncName)\n  final ${converter.enumName}${isNullable ? '?' : ''}';

    newContent = newContent.replaceRange(
      match.start,
      match.end,
      newAnnotation,
    );
    count++;
  }

  return UpdateResult(newContent, count);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      return iterator.current;
    }
    return null;
  }
}
