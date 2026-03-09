import 'dart:convert';
import 'dart:math';

enum RuleCategory { input, content, rate, upload, auth, privacy, geo, age }
enum RuleAction { allow, block, warn, escalate, redact, quarantine }
enum RuleSeverity { low, medium, high, critical }

class RuleResult {
  final bool passed;
  final RuleAction action;
  final RuleSeverity severity;
  final String ruleId;
  final String? reason;
  final Map<String, dynamic> metadata;

  const RuleResult({
    required this.passed,
    required this.action,
    required this.severity,
    required this.ruleId,
    this.reason,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'passed': passed,
    'action': action.name,
    'severity': severity.name,
    'rule_id': ruleId,
    'reason': reason,
  };
}

class RuleChainResult {
  final bool allPassed;
  final List<RuleResult> results;
  final RuleAction finalAction;
  final Duration evaluationTime;

  const RuleChainResult({
    required this.allPassed,
    required this.results,
    required this.finalAction,
    required this.evaluationTime,
  });

  List<RuleResult> get failures => results.where((r) => !r.passed).toList();

  Map<String, dynamic> toJson() => {
    'all_passed': allPassed,
    'total_rules': results.length,
    'failures': failures.length,
    'final_action': finalAction.name,
    'evaluation_ms': evaluationTime.inMilliseconds,
  };
}

class ContentPolicyConfig {
  final List<String> bannedWords;
  final List<RegExp> bannedPatterns;
  final int maxMessageLength;
  final int maxBioLength;
  final int maxUsernameLength;
  final bool allowUrls;
  final bool allowHtml;
  final int spamThresholdPerMinute;

  const ContentPolicyConfig({
    this.bannedWords = const [],
    this.bannedPatterns = const [],
    this.maxMessageLength = 5000,
    this.maxBioLength = 1000,
    this.maxUsernameLength = 30,
    this.allowUrls = true,
    this.allowHtml = false,
    this.spamThresholdPerMinute = 20,
  });
}

class RateLimitRule {
  final String actionType;
  final int maxPerWindow;
  final Duration window;
  final List<DateTime> _timestamps = [];

  RateLimitRule({
    required this.actionType,
    required this.maxPerWindow,
    required this.window,
  });

  bool check() {
    final now = DateTime.now();
    _timestamps.removeWhere((t) => now.difference(t) > window);
    if (_timestamps.length >= maxPerWindow) return false;
    _timestamps.add(now);
    return true;
  }

  int get remaining => max(0, maxPerWindow - _timestamps.length);
  double get usagePercent => _timestamps.length / maxPerWindow;
}

class UploadRule {
  final List<String> allowedMimeTypes;
  final int maxFileSizeBytes;
  final Map<String, List<int>> magicBytes;
  final bool requireMagicByteValidation;

  const UploadRule({
    required this.allowedMimeTypes,
    required this.maxFileSizeBytes,
    this.magicBytes = const {},
    this.requireMagicByteValidation = true,
  });
}

class GeoRule {
  final String regionCode;
  final bool contentAllowed;
  final List<String> blockedFeatures;
  final String? legalNotice;

  const GeoRule({
    required this.regionCode,
    this.contentAllowed = true,
    this.blockedFeatures = const [],
    this.legalNotice,
  });
}

class AgeRule {
  final int minimumAge;
  final bool requireVerification;
  final List<String> restrictedContentTypes;
  final bool parentalConsentRequired;

  const AgeRule({
    this.minimumAge = 18,
    this.requireVerification = true,
    this.restrictedContentTypes = const [],
    this.parentalConsentRequired = false,
  });
}

class PrivacyRule {
  final List<RegExp> piiPatterns;
  final bool autoRedactPii;
  final int dataRetentionDays;
  final bool allowDataExport;
  final bool allowAccountDeletion;

  PrivacyRule({
    List<RegExp>? piiPatterns,
    this.autoRedactPii = true,
    this.dataRetentionDays = 365,
    this.allowDataExport = true,
    this.allowAccountDeletion = true,
  }) : piiPatterns = piiPatterns ?? _defaultPiiPatterns;

  static final _defaultPiiPatterns = [
    RegExp(r'\b\d{3}-\d{2}-\d{4}\b'),
    RegExp(r'\b\d{16}\b'),
    RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'),
    RegExp(r'\b\d{3}[-.]?\d{3}[-.]?\d{4}\b'),
    RegExp(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b'),
  ];
}

class DeviceFingerprint {
  final String deviceId;
  final String platform;
  final String appVersion;
  final String? ipAddress;
  final String? userAgent;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int loginCount;
  final bool isTrusted;

  const DeviceFingerprint({
    required this.deviceId,
    required this.platform,
    required this.appVersion,
    this.ipAddress,
    this.userAgent,
    required this.firstSeen,
    required this.lastSeen,
    this.loginCount = 1,
    this.isTrusted = false,
  });

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'platform': platform,
    'app_version': appVersion,
    'first_seen': firstSeen.toIso8601String(),
    'last_seen': lastSeen.toIso8601String(),
    'login_count': loginCount,
    'is_trusted': isTrusted,
  };
}

class SecurityRulesService {
  final _rateLimiters = <String, RateLimitRule>{};
  final _blockedDevices = <String>{};
  final _trustedDevices = <String, DeviceFingerprint>{};

  static final _scriptPattern = RegExp(r'<script[^>]*>.*?</script>', caseSensitive: false, dotAll: true);
  static final _htmlTagPattern = RegExp(r'<[^>]+>');
  static final _sqlPattern = RegExp(r"(\b(SELECT|INSERT|UPDATE|DELETE|DROP|UNION|ALTER|CREATE|EXEC)\b)", caseSensitive: false);
  static final _xssPattern = RegExp(r'(javascript:|on\w+\s*=|eval\s*\(|document\.|window\.)', caseSensitive: false);

  bool _initialized = false;
  ContentPolicyConfig _contentPolicy = const ContentPolicyConfig();
  UploadRule _imageUploadRule = const UploadRule(allowedMimeTypes: [], maxFileSizeBytes: 0);
  UploadRule _videoUploadRule = const UploadRule(allowedMimeTypes: [], maxFileSizeBytes: 0);
  UploadRule _audioUploadRule = const UploadRule(allowedMimeTypes: [], maxFileSizeBytes: 0);
  AgeRule _ageRule = const AgeRule();
  PrivacyRule _privacyRule = PrivacyRule();
  final _geoRules = <String, GeoRule>{};

  void _ensureInitialized() {
    if (!_initialized) throw StateError('SecurityRulesService.init() must be called before use.');
  }

  Future<SecurityRulesService> init() async {
    _contentPolicy = ContentPolicyConfig(
      bannedWords: _defaultBannedWords,
      bannedPatterns: _defaultBannedPatterns,
      maxMessageLength: 5000,
      maxBioLength: 1000,
      maxUsernameLength: 30,
      allowUrls: true,
      allowHtml: false,
      spamThresholdPerMinute: 20,
    );

    _imageUploadRule = const UploadRule(
      allowedMimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
      maxFileSizeBytes: 20 * 1024 * 1024,
      magicBytes: {
        'jpeg': [0xFF, 0xD8, 0xFF],
        'png': [0x89, 0x50, 0x4E, 0x47],
        'gif': [0x47, 0x49, 0x46],
        'webp': [0x52, 0x49, 0x46, 0x46],
      },
    );

    _videoUploadRule = const UploadRule(
      allowedMimeTypes: ['video/mp4', 'video/webm', 'video/quicktime'],
      maxFileSizeBytes: 500 * 1024 * 1024,
      magicBytes: {'mp4': [0x00, 0x00, 0x00]},
    );

    _audioUploadRule = const UploadRule(
      allowedMimeTypes: ['audio/mpeg', 'audio/aac', 'audio/mp4', 'audio/wav'],
      maxFileSizeBytes: 50 * 1024 * 1024,
    );

    _ageRule = const AgeRule(
      minimumAge: 18,
      requireVerification: true,
      restrictedContentTypes: ['nsfw', 'adult', 'explicit'],
    );

    _privacyRule = PrivacyRule(
      autoRedactPii: true,
      dataRetentionDays: 365,
      allowDataExport: true,
      allowAccountDeletion: true,
    );

    _initDefaultRateLimits();
    _initDefaultGeoRules();
    _initialized = true;

    return this;
  }

  void _initDefaultRateLimits() {
    _rateLimiters['message'] = RateLimitRule(
      actionType: 'message',
      maxPerWindow: 60,
      window: const Duration(minutes: 1),
    );
    _rateLimiters['like'] = RateLimitRule(
      actionType: 'like',
      maxPerWindow: 100,
      window: const Duration(minutes: 1),
    );
    _rateLimiters['report'] = RateLimitRule(
      actionType: 'report',
      maxPerWindow: 10,
      window: const Duration(hours: 1),
    );
    _rateLimiters['upload'] = RateLimitRule(
      actionType: 'upload',
      maxPerWindow: 20,
      window: const Duration(minutes: 5),
    );
    _rateLimiters['login'] = RateLimitRule(
      actionType: 'login',
      maxPerWindow: 5,
      window: const Duration(minutes: 15),
    );
    _rateLimiters['search'] = RateLimitRule(
      actionType: 'search',
      maxPerWindow: 30,
      window: const Duration(minutes: 1),
    );
    _rateLimiters['profile_view'] = RateLimitRule(
      actionType: 'profile_view',
      maxPerWindow: 200,
      window: const Duration(minutes: 5),
    );
    _rateLimiters['api_call'] = RateLimitRule(
      actionType: 'api_call',
      maxPerWindow: 300,
      window: const Duration(minutes: 1),
    );
  }

  void _initDefaultGeoRules() {
    for (final region in ['CN', 'IR', 'KP', 'RU']) {
      _geoRules[region] = GeoRule(
        regionCode: region,
        contentAllowed: false,
        blockedFeatures: ['payment', 'upload', 'messaging'],
        legalNotice: 'Service unavailable in this region',
      );
    }
  }

  RuleChainResult evaluateInputRules(String input, {String? context}) {
    _ensureInitialized();
    final stopwatch = Stopwatch()..start();
    final results = <RuleResult>[];

    results.add(_checkXss(input));
    results.add(_checkSqlInjection(input));
    results.add(_checkScriptInjection(input));
    results.add(_checkHtmlTags(input));
    results.add(_checkContentPolicy(input));
    results.add(_checkLength(input, context));

    stopwatch.stop();
    final allPassed = results.every((r) => r.passed);
    final worstAction = allPassed
        ? RuleAction.allow
        : results.where((r) => !r.passed).fold<RuleAction>(
            RuleAction.warn,
            (prev, r) => r.action.index > prev.index ? r.action : prev,
          );

    return RuleChainResult(
      allPassed: allPassed,
      results: results,
      finalAction: worstAction,
      evaluationTime: stopwatch.elapsed,
    );
  }

  String sanitizeInput(String input) {
    _ensureInitialized();
    var sanitized = input;
    sanitized = sanitized.replaceAll(_scriptPattern, '');
    sanitized = sanitized.replaceAll(_htmlTagPattern, '');
    sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    if (_privacyRule.autoRedactPii) {
      for (final pattern in _privacyRule.piiPatterns) {
        sanitized = sanitized.replaceAll(pattern, '[REDACTED]');
      }
    }
    return sanitized.trim();
  }

  RuleResult checkRateLimit(String actionType) {
    final limiter = _rateLimiters[actionType];
    if (limiter == null) {
      return const RuleResult(
        passed: true,
        action: RuleAction.allow,
        severity: RuleSeverity.low,
        ruleId: 'rate_unknown',
      );
    }

    final allowed = limiter.check();
    return RuleResult(
      passed: allowed,
      action: allowed ? RuleAction.allow : RuleAction.block,
      severity: allowed ? RuleSeverity.low : RuleSeverity.high,
      ruleId: 'rate_$actionType',
      reason: allowed ? null : 'Rate limit exceeded for $actionType (${limiter.remaining} remaining)',
      metadata: {
        'remaining': limiter.remaining,
        'usage_percent': limiter.usagePercent,
      },
    );
  }

  RuleChainResult evaluateUploadRules({
    required String fileName,
    required int sizeBytes,
    required String mimeType,
    List<int>? headerBytes,
  }) {
    _ensureInitialized();
    final stopwatch = Stopwatch()..start();
    final results = <RuleResult>[];
    final ext = fileName.split('.').last.toLowerCase();

    UploadRule rule;
    if (mimeType.startsWith('image/')) {
      rule = _imageUploadRule;
    } else if (mimeType.startsWith('video/')) {
      rule = _videoUploadRule;
    } else if (mimeType.startsWith('audio/')) {
      rule = _audioUploadRule;
    } else {
      results.add(const RuleResult(
        passed: false,
        action: RuleAction.block,
        severity: RuleSeverity.high,
        ruleId: 'upload_type',
        reason: 'Unsupported file type',
      ));
      stopwatch.stop();
      return RuleChainResult(
        allPassed: false,
        results: results,
        finalAction: RuleAction.block,
        evaluationTime: stopwatch.elapsed,
      );
    }

    final mimeAllowed = rule.allowedMimeTypes.contains(mimeType);
    results.add(RuleResult(
      passed: mimeAllowed,
      action: mimeAllowed ? RuleAction.allow : RuleAction.block,
      severity: mimeAllowed ? RuleSeverity.low : RuleSeverity.high,
      ruleId: 'upload_mime',
      reason: mimeAllowed ? null : 'MIME type $mimeType not allowed',
    ));

    final sizeAllowed = sizeBytes <= rule.maxFileSizeBytes;
    results.add(RuleResult(
      passed: sizeAllowed,
      action: sizeAllowed ? RuleAction.allow : RuleAction.block,
      severity: sizeAllowed ? RuleSeverity.low : RuleSeverity.medium,
      ruleId: 'upload_size',
      reason: sizeAllowed ? null : 'File exceeds ${rule.maxFileSizeBytes ~/ (1024 * 1024)}MB limit',
    ));

    if (headerBytes != null && headerBytes.length >= 4 && rule.requireMagicByteValidation) {
      final expected = rule.magicBytes[ext == 'jpg' ? 'jpeg' : ext];
      if (expected != null) {
        var matches = true;
        for (var i = 0; i < expected.length && i < headerBytes.length; i++) {
          if (headerBytes[i] != expected[i]) {
            matches = false;
            break;
          }
        }
        results.add(RuleResult(
          passed: matches,
          action: matches ? RuleAction.allow : RuleAction.block,
          severity: matches ? RuleSeverity.low : RuleSeverity.critical,
          ruleId: 'upload_magic',
          reason: matches ? null : 'File header does not match declared format',
        ));
      }
    }

    final nameClean = !fileName.contains('..') && !fileName.contains('/') && !fileName.contains('\\');
    results.add(RuleResult(
      passed: nameClean,
      action: nameClean ? RuleAction.allow : RuleAction.block,
      severity: nameClean ? RuleSeverity.low : RuleSeverity.critical,
      ruleId: 'upload_path_traversal',
      reason: nameClean ? null : 'Suspicious file name detected',
    ));

    stopwatch.stop();
    final allPassed = results.every((r) => r.passed);
    return RuleChainResult(
      allPassed: allPassed,
      results: results,
      finalAction: allPassed ? RuleAction.allow : RuleAction.block,
      evaluationTime: stopwatch.elapsed,
    );
  }

  RuleResult checkGeoRestriction(String regionCode) {
    final rule = _geoRules[regionCode.toUpperCase()];
    if (rule == null || rule.contentAllowed) {
      return RuleResult(
        passed: true,
        action: RuleAction.allow,
        severity: RuleSeverity.low,
        ruleId: 'geo_$regionCode',
      );
    }
    return RuleResult(
      passed: false,
      action: RuleAction.block,
      severity: RuleSeverity.high,
      ruleId: 'geo_$regionCode',
      reason: rule.legalNotice ?? 'Region restricted',
      metadata: {'blocked_features': rule.blockedFeatures},
    );
  }

  RuleResult checkAgeVerification(int userAge) {
    final passed = userAge >= _ageRule.minimumAge;
    return RuleResult(
      passed: passed,
      action: passed ? RuleAction.allow : RuleAction.block,
      severity: passed ? RuleSeverity.low : RuleSeverity.critical,
      ruleId: 'age_verification',
      reason: passed ? null : 'Must be at least ${_ageRule.minimumAge} years old',
    );
  }

  String redactPii(String text) {
    var result = text;
    for (final pattern in _privacyRule.piiPatterns) {
      result = result.replaceAll(pattern, '[REDACTED]');
    }
    return result;
  }

  List<Map<String, dynamic>> detectPii(String text) {
    final found = <Map<String, dynamic>>[];
    for (var i = 0; i < _privacyRule.piiPatterns.length; i++) {
      final matches = _privacyRule.piiPatterns[i].allMatches(text);
      for (final m in matches) {
        found.add({
          'pattern_index': i,
          'start': m.start,
          'end': m.end,
          'length': m.end - m.start,
        });
      }
    }
    return found;
  }

  RuleResult checkDeviceFingerprint(String deviceId) {
    if (_blockedDevices.contains(deviceId)) {
      return RuleResult(
        passed: false,
        action: RuleAction.block,
        severity: RuleSeverity.critical,
        ruleId: 'device_blocked',
        reason: 'Device has been blocked',
      );
    }
    final trusted = _trustedDevices[deviceId];
    return RuleResult(
      passed: true,
      action: RuleAction.allow,
      severity: RuleSeverity.low,
      ruleId: 'device_check',
      metadata: {'is_trusted': trusted?.isTrusted ?? false},
    );
  }

  void blockDevice(String deviceId) => _blockedDevices.add(deviceId);
  void unblockDevice(String deviceId) => _blockedDevices.remove(deviceId);

  void registerDevice(DeviceFingerprint fingerprint) {
    _trustedDevices[fingerprint.deviceId] = fingerprint;
  }

  RuleResult checkSessionValidity({
    required DateTime tokenIssuedAt,
    required Duration maxSessionDuration,
    required DateTime lastActivity,
    Duration idleTimeout = const Duration(hours: 2),
  }) {
    final now = DateTime.now();
    final sessionExpired = now.difference(tokenIssuedAt) > maxSessionDuration;
    final idleExpired = now.difference(lastActivity) > idleTimeout;

    if (sessionExpired) {
      return const RuleResult(
        passed: false,
        action: RuleAction.block,
        severity: RuleSeverity.high,
        ruleId: 'session_expired',
        reason: 'Session has expired',
      );
    }

    if (idleExpired) {
      return const RuleResult(
        passed: false,
        action: RuleAction.warn,
        severity: RuleSeverity.medium,
        ruleId: 'session_idle',
        reason: 'Session idle timeout',
      );
    }

    return const RuleResult(
      passed: true,
      action: RuleAction.allow,
      severity: RuleSeverity.low,
      ruleId: 'session_valid',
    );
  }

  void updateContentPolicy(ContentPolicyConfig policy) {
    _contentPolicy = policy;
  }

  void addGeoRule(GeoRule rule) {
    _geoRules[rule.regionCode] = rule;
  }

  void addRateLimit(RateLimitRule rule) {
    _rateLimiters[rule.actionType] = rule;
  }

  Map<String, dynamic> getRateLimitStatus() {
    return _rateLimiters.map((key, limiter) => MapEntry(key, {
      'remaining': limiter.remaining,
      'usage_percent': limiter.usagePercent,
    }));
  }

  RuleResult _checkXss(String input) {
    final hasXss = _xssPattern.hasMatch(input);
    return RuleResult(
      passed: !hasXss,
      action: hasXss ? RuleAction.block : RuleAction.allow,
      severity: hasXss ? RuleSeverity.critical : RuleSeverity.low,
      ruleId: 'input_xss',
      reason: hasXss ? 'Potential XSS detected' : null,
    );
  }

  RuleResult _checkSqlInjection(String input) {
    final hasSql = _sqlPattern.hasMatch(input);
    return RuleResult(
      passed: !hasSql,
      action: hasSql ? RuleAction.block : RuleAction.allow,
      severity: hasSql ? RuleSeverity.critical : RuleSeverity.low,
      ruleId: 'input_sql',
      reason: hasSql ? 'Potential SQL injection detected' : null,
    );
  }

  RuleResult _checkScriptInjection(String input) {
    final hasScript = _scriptPattern.hasMatch(input);
    return RuleResult(
      passed: !hasScript,
      action: hasScript ? RuleAction.block : RuleAction.allow,
      severity: hasScript ? RuleSeverity.critical : RuleSeverity.low,
      ruleId: 'input_script',
      reason: hasScript ? 'Script injection detected' : null,
    );
  }

  RuleResult _checkHtmlTags(String input) {
    if (_contentPolicy.allowHtml) {
      return const RuleResult(
        passed: true,
        action: RuleAction.allow,
        severity: RuleSeverity.low,
        ruleId: 'input_html',
      );
    }
    final hasHtml = _htmlTagPattern.hasMatch(input);
    return RuleResult(
      passed: !hasHtml,
      action: hasHtml ? RuleAction.warn : RuleAction.allow,
      severity: hasHtml ? RuleSeverity.medium : RuleSeverity.low,
      ruleId: 'input_html',
      reason: hasHtml ? 'HTML tags not allowed' : null,
    );
  }

  RuleResult _checkContentPolicy(String input) {
    final lower = input.toLowerCase();
    for (final word in _contentPolicy.bannedWords) {
      if (lower.contains(word.toLowerCase())) {
        return RuleResult(
          passed: false,
          action: RuleAction.block,
          severity: RuleSeverity.high,
          ruleId: 'content_banned_word',
          reason: 'Content contains prohibited language',
        );
      }
    }
    for (final pattern in _contentPolicy.bannedPatterns) {
      if (pattern.hasMatch(input)) {
        return RuleResult(
          passed: false,
          action: RuleAction.block,
          severity: RuleSeverity.high,
          ruleId: 'content_banned_pattern',
          reason: 'Content matches prohibited pattern',
        );
      }
    }
    return const RuleResult(
      passed: true,
      action: RuleAction.allow,
      severity: RuleSeverity.low,
      ruleId: 'content_policy',
    );
  }

  RuleResult _checkLength(String input, String? context) {
    final maxLen = switch (context) {
      'message' => _contentPolicy.maxMessageLength,
      'bio' => _contentPolicy.maxBioLength,
      'username' => _contentPolicy.maxUsernameLength,
      _ => _contentPolicy.maxMessageLength,
    };
    final withinLimit = input.length <= maxLen;
    return RuleResult(
      passed: withinLimit,
      action: withinLimit ? RuleAction.allow : RuleAction.block,
      severity: withinLimit ? RuleSeverity.low : RuleSeverity.medium,
      ruleId: 'input_length',
      reason: withinLimit ? null : 'Input exceeds $maxLen character limit',
    );
  }

  static final _defaultBannedWords = <String>[
    'phishing',
    'malware',
    'ransomware',
    'scam',
    'fraud',
  ];

  static final _defaultBannedPatterns = <RegExp>[
    RegExp(r'(?:bit\.ly|tinyurl|goo\.gl)/\w+', caseSensitive: false),
    RegExp(r'send\s+(?:money|bitcoin|crypto|btc|eth)', caseSensitive: false),
    RegExp(r'(?:wire|transfer)\s+\$?\d+', caseSensitive: false),
    RegExp(r'(?:ssn|social\s*security)\s*:?\s*\d', caseSensitive: false),
  ];

  void dispose() {
    _rateLimiters.clear();
    _blockedDevices.clear();
    _trustedDevices.clear();
  }
}
