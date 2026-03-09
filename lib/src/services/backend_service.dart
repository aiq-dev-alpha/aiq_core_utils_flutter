import 'dart:async';
import 'dart:convert';

enum HttpMethod { get, post, put, patch, delete }

class ApiResponse<T> {
  final int statusCode;
  final T? data;
  final String? error;
  final Map<String, String> headers;
  final Duration elapsed;

  const ApiResponse({
    required this.statusCode,
    this.data,
    this.error,
    this.headers = const {},
    this.elapsed = Duration.zero,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  bool get isError => !isSuccess;
  bool get isUnauthorized => statusCode == 401;
  bool get isRateLimited => statusCode == 429;
  bool get isForbidden => statusCode == 403;
}

class ApiEndpoint {
  final String path;
  final HttpMethod method;
  final bool requiresAuth;
  final Duration? cacheTimeout;
  final int? rateLimitPerMinute;

  const ApiEndpoint({
    required this.path,
    this.method = HttpMethod.get,
    this.requiresAuth = true,
    this.cacheTimeout,
    this.rateLimitPerMinute,
  });
}

class RateLimitState {
  final int remaining;
  final int limit;
  final DateTime resetsAt;

  const RateLimitState({
    required this.remaining,
    required this.limit,
    required this.resetsAt,
  });

  bool get isLimited => remaining <= 0 && DateTime.now().isBefore(resetsAt);
}

class SecurityHeaders {
  static const Map<String, String> defaults = {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'X-XSS-Protection': '1; mode=block',
    'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
    'Content-Security-Policy': "default-src 'self'",
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=(self)',
  };

  static const Map<String, String> corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Request-ID',
    'Access-Control-Max-Age': '86400',
    'Access-Control-Expose-Headers': 'X-RateLimit-Remaining, X-RateLimit-Reset',
  };
}

class DatabaseCollection {
  final String name;
  final List<String> indexes;
  final Map<String, String> schema;

  const DatabaseCollection({
    required this.name,
    this.indexes = const [],
    this.schema = const {},
  });
}

class CloudStorageConfig {
  final String bucket;
  final String region;
  final int maxUploadSizeMb;
  final List<String> allowedMimeTypes;
  final String cdnBaseUrl;

  const CloudStorageConfig({
    this.bucket = 'app-media',
    this.region = 'us-east-1',
    this.maxUploadSizeMb = 50,
    this.allowedMimeTypes = const ['image/jpeg', 'image/png', 'image/webp', 'video/mp4'],
    this.cdnBaseUrl = 'https://cdn.example.com',
  });
}

class UploadResult {
  final String url;
  final String cdnUrl;
  final String fileId;
  final String mimeType;
  final int sizeBytes;
  final DateTime uploadedAt;

  const UploadResult({
    required this.url,
    required this.cdnUrl,
    required this.fileId,
    required this.mimeType,
    required this.sizeBytes,
    required this.uploadedAt,
  });

  Map<String, dynamic> toJson() => {
    'url': url,
    'cdn_url': cdnUrl,
    'file_id': fileId,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'uploaded_at': uploadedAt.toIso8601String(),
  };

  factory UploadResult.fromJson(Map<String, dynamic> j) => UploadResult(
    url: j['url'] ?? '',
    cdnUrl: j['cdn_url'] ?? '',
    fileId: j['file_id'] ?? '',
    mimeType: j['mime_type'] ?? '',
    sizeBytes: j['size_bytes'] ?? 0,
    uploadedAt: DateTime.tryParse(j['uploaded_at'] ?? '') ?? DateTime.now(),
  );
}

class BackendService {
  bool _isConnected = true;
  final _rateLimits = <String, RateLimitState>{};
  final _responseCache = <String, _CachedResponse>{};
  final List<Map<String, dynamic>> _requestLog = [];
  String? _authToken;
  final storageConfig = const CloudStorageConfig();

  bool get isConnected => _isConnected;
  List<Map<String, dynamic>> get requestLog => List.unmodifiable(_requestLog);

  static const collections = [
    DatabaseCollection(
      name: 'users',
      indexes: ['email', 'phone', 'display_name', 'created_at'],
      schema: {'uid': 'string', 'email': 'string', 'phone': 'string', 'display_name': 'string',
        'photo_url': 'string', 'bio': 'string', 'role': 'string', 'created_at': 'timestamp',
        'updated_at': 'timestamp', 'is_active': 'boolean', 'settings': 'map'},
    ),
    DatabaseCollection(
      name: 'profiles',
      indexes: ['user_id', 'location', 'age', 'is_visible'],
      schema: {'user_id': 'string', 'age': 'number', 'gender': 'string', 'location': 'geopoint',
        'interests': 'array', 'photos': 'array', 'is_verified': 'boolean', 'is_bot': 'boolean'},
    ),
    DatabaseCollection(
      name: 'messages',
      indexes: ['channel_id', 'sender_id', 'created_at'],
      schema: {'channel_id': 'string', 'sender_id': 'string', 'text': 'string',
        'media_url': 'string', 'type': 'string', 'created_at': 'timestamp', 'is_read': 'boolean'},
    ),
    DatabaseCollection(
      name: 'matches',
      indexes: ['user_a', 'user_b', 'created_at', 'status'],
      schema: {'user_a': 'string', 'user_b': 'string', 'status': 'string',
        'created_at': 'timestamp', 'updated_at': 'timestamp'},
    ),
    DatabaseCollection(
      name: 'transactions',
      indexes: ['user_id', 'type', 'status', 'created_at'],
      schema: {'user_id': 'string', 'type': 'string', 'amount': 'number', 'currency': 'string',
        'status': 'string', 'provider': 'string', 'receipt_id': 'string', 'created_at': 'timestamp'},
    ),
    DatabaseCollection(
      name: 'subscriptions',
      indexes: ['user_id', 'product_id', 'status', 'expires_at'],
      schema: {'user_id': 'string', 'product_id': 'string', 'tier': 'string',
        'status': 'string', 'started_at': 'timestamp', 'expires_at': 'timestamp', 'auto_renew': 'boolean'},
    ),
    DatabaseCollection(
      name: 'reports',
      indexes: ['reporter_id', 'reported_id', 'status', 'created_at'],
      schema: {'reporter_id': 'string', 'reported_id': 'string', 'reason': 'string',
        'details': 'string', 'evidence': 'array', 'status': 'string', 'created_at': 'timestamp'},
    ),
    DatabaseCollection(
      name: 'notifications',
      indexes: ['user_id', 'type', 'is_read', 'created_at'],
      schema: {'user_id': 'string', 'type': 'string', 'title': 'string', 'body': 'string',
        'data': 'map', 'is_read': 'boolean', 'created_at': 'timestamp'},
    ),
  ];

  Future<BackendService> init() async {
    return this;
  }

  void setAuthToken(String token) => _authToken = token;
  void clearAuthToken() => _authToken = null;

  Future<ApiResponse<Map<String, dynamic>>> request(
    ApiEndpoint endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    final start = DateTime.now();
    final key = '${endpoint.method.name}:${endpoint.path}';

    if (_rateLimits.containsKey(key) && _rateLimits[key]!.isLimited) {
      return ApiResponse(
        statusCode: 429,
        error: 'Rate limit exceeded',
        elapsed: DateTime.now().difference(start),
      );
    }

    if (endpoint.requiresAuth && _authToken == null) {
      return ApiResponse(
        statusCode: 401,
        error: 'Authentication required',
        elapsed: DateTime.now().difference(start),
      );
    }

    if (endpoint.cacheTimeout != null && endpoint.method == HttpMethod.get) {
      final cached = _responseCache[key];
      if (cached != null && !cached.isExpired) {
        return ApiResponse(
          statusCode: 200,
          data: cached.data,
          elapsed: DateTime.now().difference(start),
        );
      }
    }

    await Future.delayed(const Duration(milliseconds: 100));

    final response = <String, dynamic>{
      'success': true,
      'timestamp': DateTime.now().toIso8601String(),
    };

    if (endpoint.cacheTimeout != null) {
      _responseCache[key] = _CachedResponse(
        data: response,
        cachedAt: DateTime.now(),
        timeout: endpoint.cacheTimeout!,
      );
    }

    _updateRateLimit(key, endpoint.rateLimitPerMinute ?? 60);

    _requestLog.add({
      'method': endpoint.method.name.toUpperCase(),
      'path': endpoint.path,
      'status': 200,
      'elapsed_ms': DateTime.now().difference(start).inMilliseconds,
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (_requestLog.length > 100) _requestLog.removeAt(0);

    return ApiResponse(
      statusCode: 200,
      data: response,
      headers: {
        ...SecurityHeaders.defaults,
        'X-RateLimit-Remaining': '${_rateLimits[key]?.remaining ?? 60}',
        'X-RateLimit-Reset': (_rateLimits[key]?.resetsAt ?? DateTime.now()).toIso8601String(),
      },
      elapsed: DateTime.now().difference(start),
    );
  }

  Future<UploadResult> uploadMedia({
    required String fileName,
    required String mimeType,
    required int sizeBytes,
    String? folder,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));

    if (sizeBytes > storageConfig.maxUploadSizeMb * 1024 * 1024) {
      throw Exception('File size exceeds ${storageConfig.maxUploadSizeMb}MB limit');
    }

    if (!storageConfig.allowedMimeTypes.contains(mimeType)) {
      throw Exception('File type $mimeType not allowed');
    }

    final fileId = 'file_${DateTime.now().millisecondsSinceEpoch}';
    final path = folder != null ? '$folder/$fileId' : fileId;
    return UploadResult(
      url: 'https://storage.example.com/${storageConfig.bucket}/$path',
      cdnUrl: '${storageConfig.cdnBaseUrl}/$path',
      fileId: fileId,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      uploadedAt: DateTime.now(),
    );
  }

  Future<String> getCdnUrl(String fileId) async {
    return '${storageConfig.cdnBaseUrl}/$fileId';
  }

  RateLimitState? getRateLimit(String endpoint) => _rateLimits[endpoint];

  void _updateRateLimit(String key, int limitPerMinute) {
    final current = _rateLimits[key];
    if (current == null || current.resetsAt.isBefore(DateTime.now())) {
      _rateLimits[key] = RateLimitState(
        remaining: limitPerMinute - 1,
        limit: limitPerMinute,
        resetsAt: DateTime.now().add(const Duration(minutes: 1)),
      );
    } else {
      _rateLimits[key] = RateLimitState(
        remaining: (current.remaining - 1).clamp(0, current.limit),
        limit: current.limit,
        resetsAt: current.resetsAt,
      );
    }
  }

  void clearCache() => _responseCache.clear();
  void clearRateLimits() => _rateLimits.clear();
  void clearRequestLog() => _requestLog.clear();

  void dispose() {
    _responseCache.clear();
    _rateLimits.clear();
  }
}

class _CachedResponse {
  final Map<String, dynamic> data;
  final DateTime cachedAt;
  final Duration timeout;

  _CachedResponse({required this.data, required this.cachedAt, required this.timeout});

  bool get isExpired => DateTime.now().isAfter(cachedAt.add(timeout));
}
