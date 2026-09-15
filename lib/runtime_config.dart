import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The deliberately small, server-controlled surface.  This document may
/// change copy and navigation presentation, but it cannot change workflows or
/// introduce arbitrary UI/action payloads.
class RuntimeConfig {
  const RuntimeConfig({
    required this.schemaVersion,
    required this.version,
    required this.copy,
    required this.sections,
    required this.refreshInterval,
    required this.refreshIntervals,
    required this.features,
  });

  static const int supportedSchemaVersion = 1;
  static const String cacheKey = 'content-doctor.runtime-config.v1';
  static const Duration defaultRefreshInterval = Duration(minutes: 5);

  final int schemaVersion;
  final String version;
  final Map<String, String> copy;
  final List<String> sections;
  final Duration refreshInterval;
  final Map<String, Duration> refreshIntervals;
  final Map<String, bool> features;

  static const List<String> knownSections = <String>[
    'review',
    'schedule',
    'studio',
    'results',
    'accounts',
    'team',
  ];

  static const List<String> refreshableSections = <String>[
    'review',
    'schedule',
    'results',
    'team',
  ];

  static const List<String> knownFeatures = <String>[
    'phone_upload',
    'generation',
    'crew_chat',
    'analytics',
    'dm_workspace',
    'tab_review',
    'tab_schedule',
    'tab_studio',
    'tab_results',
    'tab_accounts',
    'tab_team',
  ];

  static RuntimeConfig defaults() => const RuntimeConfig(
    schemaVersion: supportedSchemaVersion,
    version: 'default',
    copy: <String, String>{},
    sections: knownSections,
    refreshInterval: defaultRefreshInterval,
    refreshIntervals: <String, Duration>{},
    features: <String, bool>{},
  );

  /// Returns null for malformed, unsupported, or unsafe documents.
  static RuntimeConfig? parse(Object? raw) {
    if (raw is! Map) return null;
    final dynamic schema = raw['schema_version'];
    if (schema is! num || schema.toInt() != supportedSchemaVersion) return null;
    final dynamic version = raw['version'];
    if (version is! String || version.trim().isEmpty || version.length > 80) {
      return null;
    }

    final Map<String, String> copy = <String, String>{};
    final dynamic rawCopy = raw['copy'];
    if (rawCopy != null) {
      if (rawCopy is! Map) return null;
      for (final MapEntry<Object?, Object?> entry in rawCopy.entries) {
        if (entry.key is! String || entry.value is! String) return null;
        final String key = entry.key as String;
        final String value = (entry.value as String).trim();
        if (key.isEmpty || key.length > 80 || value.length > 240) return null;
        copy[key] = value;
      }
    }

    final List<String> sections = <String>[];
    final dynamic rawSections = raw['sections'];
    if (rawSections != null) {
      if (rawSections is! List) return null;
      for (final dynamic value in rawSections) {
        if (value is! String || !knownSections.contains(value)) return null;
        if (!sections.contains(value)) {
          sections.add(value);
        }
      }
    }
    if (sections.isEmpty) sections.addAll(knownSections);
    final dynamic visibility = raw['section_visibility'];
    if (visibility != null) {
      if (visibility is! Map) return null;
      for (final MapEntry<Object?, Object?> entry in visibility.entries) {
        if (entry.key is! String ||
            entry.value is! bool ||
            !knownSections.contains(entry.key)) {
          return null;
        }
        if (entry.value == false) {
          sections.remove(entry.key as String);
        }
      }
    }

    final dynamic seconds = raw['refresh_interval_seconds'];
    final int refreshSeconds = seconds is num
        ? seconds.toInt().clamp(15, 3600).toInt()
        : defaultRefreshInterval.inSeconds;

    final Map<String, Duration> refreshIntervals = <String, Duration>{};
    final dynamic rawRefreshes = raw['refresh_seconds'];
    if (rawRefreshes != null) {
      if (rawRefreshes is! Map) return null;
      for (final MapEntry<Object?, Object?> entry in rawRefreshes.entries) {
        if (entry.key is! String ||
            !refreshableSections.contains(entry.key) ||
            entry.value is! num) {
          return null;
        }
        final int value = (entry.value as num).toInt();
        if (value < 3 || value > 3600) return null;
        refreshIntervals[entry.key as String] = Duration(seconds: value);
      }
    }

    final Map<String, bool> features = <String, bool>{};
    final dynamic rawFeatures = raw['features'];
    if (rawFeatures != null) {
      if (rawFeatures is! Map) return null;
      for (final MapEntry<Object?, Object?> entry in rawFeatures.entries) {
        if (entry.key is! String ||
            entry.value is! bool ||
            !knownFeatures.contains(entry.key)) {
          return null;
        }
        features[entry.key as String] = entry.value as bool;
      }
    }
    return RuntimeConfig(
      schemaVersion: supportedSchemaVersion,
      version: version.trim(),
      copy: Map<String, String>.unmodifiable(copy),
      sections: List<String>.unmodifiable(sections),
      refreshInterval: Duration(seconds: refreshSeconds),
      refreshIntervals: Map<String, Duration>.unmodifiable(refreshIntervals),
      features: Map<String, bool>.unmodifiable(features),
    );
  }

  static RuntimeConfig? decode(String value) {
    try {
      return parse(jsonDecode(value));
    } on Object {
      return null;
    }
  }

  String? text(String key) => copy[key];
  bool feature(String key, {bool fallback = true}) => features[key] ?? fallback;
  Duration refreshFor(String section) =>
      refreshIntervals[section] ?? refreshInterval;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'schema_version': schemaVersion,
    'version': version,
    'copy': copy,
    'sections': sections,
    'section_visibility': {
      for (final String section in knownSections)
        section: sections.contains(section),
    },
    'refresh_interval_seconds': refreshInterval.inSeconds,
    'refresh_seconds': {
      for (final MapEntry<String, Duration> entry in refreshIntervals.entries)
        entry.key: entry.value.inSeconds,
    },
    'features': features,
  };

  static Future<RuntimeConfig> loadCached(SharedPreferences prefs) async =>
      decode(prefs.getString(cacheKey) ?? '') ?? defaults();

  Future<void> save(SharedPreferences prefs) =>
      prefs.setString(cacheKey, jsonEncode(toJson()));
}

typedef RuntimeConfigFetch = Future<Object?> Function();

/// Fetches a last-known-good document. Network failures never replace a good
/// cache, and a bad server document is ignored rather than applied.
class RuntimeConfigRepository {
  const RuntimeConfigRepository(this.fetch);
  final RuntimeConfigFetch fetch;

  Future<RuntimeConfig> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final RuntimeConfig cached = await RuntimeConfig.loadCached(prefs);
    try {
      final RuntimeConfig? fresh = RuntimeConfig.parse(await fetch());
      if (fresh != null) {
        await fresh.save(prefs);
        return fresh;
      }
    } on Object {
      // Keep the last-known-good value on every transport/parse failure.
    }
    return cached;
  }
}
