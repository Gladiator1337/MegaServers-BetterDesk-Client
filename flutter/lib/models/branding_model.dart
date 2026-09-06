import 'dart:io';

import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const int kBrandingLogoMaxBytes = 512 * 1024;
const String kBrandingLogoFileName = 'betterdesk_branding_logo';

final _brandingLogoExts = <String>{'.png', '.jpg', '.jpeg', '.webp'};

class BrandingModel {
  static BrandingModel get current {
    if (!Get.isRegistered<BrandingModel>()) {
      Get.put(BrandingModel(), permanent: true);
    }
    return Get.find<BrandingModel>();
  }

  final companyName = ''.obs;
  final phone = ''.obs;
  final email = ''.obs;
  final website = ''.obs;
  final hasLogo = false.obs;
  final logoPath = ''.obs;

  BrandingModel() {
    load();
  }

  bool get hasCompanyName => companyName.value.trim().isNotEmpty;

  bool get hasContactOrLogo =>
      hasLogo.value ||
      phone.value.trim().isNotEmpty ||
      email.value.trim().isNotEmpty ||
      website.value.trim().isNotEmpty;

  bool get hasBranding => hasCompanyName || hasContactOrLogo;

  void load() {
    companyName.value =
        bind.mainGetLocalOption(key: kOptionBrandingCompanyName);
    phone.value = bind.mainGetLocalOption(key: kOptionBrandingPhone);
    email.value = bind.mainGetLocalOption(key: kOptionBrandingEmail);
    website.value = bind.mainGetLocalOption(key: kOptionBrandingWebsite);
    final logoFlag = bind.mainGetLocalOption(key: kOptionBrandingLogo);
    if (logoFlag == 'Y') {
      _resolveLogoPath().then((p) {
        if (p != null && File(p).existsSync()) {
          logoPath.value = p;
          hasLogo.value = true;
        } else {
          logoPath.value = '';
          hasLogo.value = false;
        }
      });
    } else {
      logoPath.value = '';
      hasLogo.value = false;
    }
  }

  Future<String?> _resolveLogoPath() async {
    final dir = await getApplicationSupportDirectory();
    for (final ext in _brandingLogoExts) {
      final candidate = path.join(dir.path, '$kBrandingLogoFileName$ext');
      if (await File(candidate).exists()) {
        return candidate;
      }
    }
    return null;
  }

  Future<String> _destLogoPath(String ext) async {
    final dir = await getApplicationSupportDirectory();
    return path.join(dir.path, '$kBrandingLogoFileName$ext');
  }

  Future<void> _deleteLogoFiles() async {
    final dir = await getApplicationSupportDirectory();
    for (final ext in _brandingLogoExts) {
      final f = File(path.join(dir.path, '$kBrandingLogoFileName$ext'));
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  /// Returns an error translation key on failure, or null on success.
  Future<String?> setLogoFromPath(String sourcePath) async {
    final ext = path.extension(sourcePath).toLowerCase();
    if (!_brandingLogoExts.contains(ext)) {
      return 'Invalid logo format';
    }
    final src = File(sourcePath);
    if (!await src.exists()) {
      return 'Invalid logo format';
    }
    final len = await src.length();
    if (len <= 0 || len > kBrandingLogoMaxBytes) {
      return 'Logo too large';
    }
    await _deleteLogoFiles();
    final dest = await _destLogoPath(ext);
    await src.copy(dest);
    await bind.mainSetLocalOption(key: kOptionBrandingLogo, value: 'Y');
    logoPath.value = dest;
    hasLogo.value = true;
    return null;
  }

  Future<void> removeLogo() async {
    await _deleteLogoFiles();
    await bind.mainSetLocalOption(key: kOptionBrandingLogo, value: '');
    logoPath.value = '';
    hasLogo.value = false;
  }

  Future<void> save({
    required String company,
    required String phoneValue,
    required String emailValue,
    required String websiteValue,
  }) async {
    final c = company.trim();
    final p = phoneValue.trim();
    final e = emailValue.trim();
    final w = websiteValue.trim();
    await bind.mainSetLocalOption(key: kOptionBrandingCompanyName, value: c);
    await bind.mainSetLocalOption(key: kOptionBrandingPhone, value: p);
    await bind.mainSetLocalOption(key: kOptionBrandingEmail, value: e);
    await bind.mainSetLocalOption(key: kOptionBrandingWebsite, value: w);
    companyName.value = c;
    phone.value = p;
    email.value = e;
    website.value = w;
  }

  Future<void> clear() async {
    await bind.mainSetLocalOption(key: kOptionBrandingCompanyName, value: '');
    await bind.mainSetLocalOption(key: kOptionBrandingPhone, value: '');
    await bind.mainSetLocalOption(key: kOptionBrandingEmail, value: '');
    await bind.mainSetLocalOption(key: kOptionBrandingWebsite, value: '');
    await removeLogo();
    companyName.value = '';
    phone.value = '';
    email.value = '';
    website.value = '';
  }

  static String normalizeWebsiteUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }
}
