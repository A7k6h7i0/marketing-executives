import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local vault of organisation registration details for super-admin review.
/// Production pending API often returns null contact fields; this keeps the
/// full form (including owner password) when the request was submitted from
/// this app, and lets super-admin keep approved org records with slug.
class OrganisationRegistry {
  static const prefsKey = 'organisation_registry_v1';
  static const _key = prefsKey;

  static Future<List<Map<String, dynamic>>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(items));
  }

  static Future<void> upsert(Map<String, dynamic> org) async {
    final slug = (org['slug'] ?? org['org_slug'] ?? '').toString().toLowerCase();
    final id = org['id']?.toString();
    if (slug.isEmpty && (id == null || id.isEmpty)) return;

    final all = await loadAll();
    final idx = all.indexWhere((item) {
      final s = (item['slug'] ?? '').toString().toLowerCase();
      final i = item['id']?.toString();
      return (slug.isNotEmpty && s == slug) || (id != null && i == id);
    });
    final existing = idx >= 0 ? all[idx] : <String, dynamic>{};
    // Never let null/empty API fields wipe previously saved registration details.
    String? pick(String key, [String? alt]) {
      final next = org[key] ?? (alt == null ? null : org[alt]);
      if (next != null && next.toString().trim().isNotEmpty) return next.toString();
      final prev = existing[key];
      if (prev != null && prev.toString().trim().isNotEmpty) return prev.toString();
      return next?.toString();
    }

    final merged = {
      ...existing,
      ...org,
      if (slug.isNotEmpty) 'slug': slug,
      'name': pick('name', 'org_name') ?? existing['name'] ?? 'Organisation',
      'email': pick('email', 'org_email'),
      'phone': pick('phone', 'org_phone'),
      'address': pick('address', 'org_address'),
      'owner_name': pick('owner_name'),
      'owner_email': pick('owner_email'),
      'owner_password': pick('owner_password'),
      'owner_phone': pick('owner_phone'),
      'status': pick('status') ?? existing['status'] ?? 'pending',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (idx >= 0) {
      all[idx] = merged;
    } else {
      all.add(merged);
    }
    await _saveAll(all);
  }

  /// Keep previously approved orgs visible even when pending API is empty.
  static Future<void> ensureKnownOrganisations() async {
    await upsert({
      'name': 'Digital Linka',
      'slug': 'digital-linka',
      'status': 'active',
    });
    await upsert({
      'id': '90fa6b49-3cc0-4ac6-8f0a-4623eaa5fc70',
      'name': 'Full Meta Org',
      'slug': 'fullmeta56759',
      'status': 'active',
    });
    await upsert({
      'name': 'AddPhoneBook',
      'slug': 'addphonebook',
      'status': 'active',
      'email': 'info@addphonebook.com',
    });
  }

  static Future<Map<String, dynamic>?> findBySlug(String slug) async {
    final key = slug.trim().toLowerCase();
    if (key.isEmpty) return null;
    final all = await loadAll();
    for (final item in all) {
      if ((item['slug'] ?? '').toString().toLowerCase() == key) return item;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> findById(String id) async {
    final all = await loadAll();
    for (final item in all) {
      if (item['id']?.toString() == id) return item;
    }
    return null;
  }
}
