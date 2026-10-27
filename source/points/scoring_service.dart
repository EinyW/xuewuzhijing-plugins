import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scoring_profile.dart';

class ScoringService {
  ScoringService._();
  static final instance = ScoringService._();
  static const storageKey = 'scoring_profile_v1';
  final profile = ValueNotifier<ScoringProfile>(const ScoringProfile());
  bool _loaded = false;

  Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    var value = const ScoringProfile();
    if (raw != null) {
      try {
        value = decode(raw);
      } on FormatException {
        /* 保留损坏文件，使用默认方案。 */
      }
    }
    profile.value = value;
    _loaded = true;
  }

  Future<void> save(ScoringProfile value) async {
    value.validate();
    final frozen = ScoringProfile.fromJson(value.toJson());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, encode(frozen));
    profile.value = frozen;
    _loaded = true;
  }

  String encode([ScoringProfile? value]) {
    final selected = value ?? profile.value;
    selected.validate();
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'quiz_app_scoring',
      'version': 1,
      'profile': selected.toJson(),
    });
  }

  ScoringProfile decode(String raw) {
    try {
      if (raw.length > 1048576) throw const FormatException('积分方案文件不能超过 1 MB');
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['format'] != 'quiz_app_scoring' ||
          data['version'] != 1 ||
          data['profile'] is! Map) {
        throw const FormatException('请选择本软件导出的积分方案（版本 1）');
      }
      return ScoringProfile.fromJson(
        Map<String, dynamic>.from(data['profile'] as Map),
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('无法读取积分方案');
    }
  }

  Future<void> importJson(String raw) async {
    final value = decode(raw);
    await save(value);
  }

  Future<void> reset() => save(const ScoringProfile());
}
