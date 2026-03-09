import 'dart:math';

enum PipelineStage { upload, validate, parse, sanitize, process, store, deliver }
enum PipelineStatus { queued, processing, completed, failed, cancelled }
enum ProcessingAction { thumbnail, transcode, watermark, compress, resize, blur }
enum DeliveryStrategy { cdn, direct, adaptive, cached }

class PipelineJob {
  final String id;
  final String uploaderId;
  final String fileName;
  final int sizeBytes;
  final String mimeType;
  final PipelineStage currentStage;
  final PipelineStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? error;
  final Map<String, dynamic> stageResults;
  final List<ProcessingAction> pendingActions;
  final List<ProcessingAction> completedActions;
  final double progress;

  const PipelineJob({
    required this.id,
    required this.uploaderId,
    required this.fileName,
    required this.sizeBytes,
    required this.mimeType,
    required this.currentStage,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.error,
    this.stageResults = const {},
    this.pendingActions = const [],
    this.completedActions = const [],
    this.progress = 0.0,
  });

  PipelineJob copyWith({
    PipelineStage? currentStage,
    PipelineStatus? status,
    DateTime? completedAt,
    String? error,
    Map<String, dynamic>? stageResults,
    List<ProcessingAction>? pendingActions,
    List<ProcessingAction>? completedActions,
    double? progress,
  }) => PipelineJob(
    id: id,
    uploaderId: uploaderId,
    fileName: fileName,
    sizeBytes: sizeBytes,
    mimeType: mimeType,
    currentStage: currentStage ?? this.currentStage,
    status: status ?? this.status,
    createdAt: createdAt,
    completedAt: completedAt ?? this.completedAt,
    error: error ?? this.error,
    stageResults: stageResults ?? this.stageResults,
    pendingActions: pendingActions ?? this.pendingActions,
    completedActions: completedActions ?? this.completedActions,
    progress: progress ?? this.progress,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'uploader_id': uploaderId,
    'file_name': fileName,
    'size_bytes': sizeBytes,
    'mime_type': mimeType,
    'current_stage': currentStage.name,
    'status': status.name,
    'created_at': createdAt.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'error': error,
    'progress': progress,
  };
}

class ThumbnailConfig {
  final int width;
  final int height;
  final int quality;
  final String format;

  const ThumbnailConfig({
    this.width = 300,
    this.height = 300,
    this.quality = 80,
    this.format = 'webp',
  });
}

class TranscodeConfig {
  final String targetFormat;
  final int maxBitrate;
  final int maxWidth;
  final int maxHeight;
  final bool stripAudio;

  const TranscodeConfig({
    this.targetFormat = 'mp4',
    this.maxBitrate = 5000000,
    this.maxWidth = 1920,
    this.maxHeight = 1080,
    this.stripAudio = false,
  });
}

class WatermarkConfig {
  final String text;
  final double opacity;
  final String position;
  final int fontSize;

  const WatermarkConfig({
    this.text = '',
    this.opacity = 0.3,
    this.position = 'bottom_right',
    this.fontSize = 14,
  });
}

class CdnConfig {
  final String bucketName;
  final String region;
  final String baseUrl;
  final Duration cacheMaxAge;
  final bool enableAdaptiveQuality;
  final List<int> qualityVariants;

  const CdnConfig({
    this.bucketName = 'content-pipeline',
    this.region = 'us-east-1',
    this.baseUrl = 'https://cdn.example.com',
    this.cacheMaxAge = const Duration(days: 30),
    this.enableAdaptiveQuality = true,
    this.qualityVariants = const [360, 720, 1080],
  });
}

class ContentRemovalRequest {
  final String contentId;
  final String reason;
  final String requesterId;
  final bool isDmca;
  final DateTime requestedAt;
  final bool autoExpire;
  final DateTime? expireAt;

  const ContentRemovalRequest({
    required this.contentId,
    required this.reason,
    required this.requesterId,
    this.isDmca = false,
    required this.requestedAt,
    this.autoExpire = false,
    this.expireAt,
  });
}

class MigrationJob {
  final String id;
  final String sourcePlatform;
  final int totalItems;
  final int processedItems;
  final int failedItems;
  final PipelineStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;

  const MigrationJob({
    required this.id,
    required this.sourcePlatform,
    required this.totalItems,
    required this.processedItems,
    required this.failedItems,
    required this.status,
    required this.startedAt,
    this.completedAt,
  });

  double get progressPercent => totalItems > 0 ? processedItems / totalItems : 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'source_platform': sourcePlatform,
    'total_items': totalItems,
    'processed_items': processedItems,
    'failed_items': failedItems,
    'status': status.name,
    'progress_percent': progressPercent,
  };
}

class ContentPipelineService {
  final _random = Random();
  final _activeJobs = <String, PipelineJob>{};
  final _completedJobs = <PipelineJob>[];
  final _removalQueue = <ContentRemovalRequest>[];
  final _migrations = <String, MigrationJob>{};

  bool _initialized = false;
  CdnConfig _cdnConfig = const CdnConfig();
  ThumbnailConfig _thumbnailConfig = const ThumbnailConfig();
  TranscodeConfig _transcodeConfig = const TranscodeConfig();

  ThumbnailConfig get thumbnailConfig => _thumbnailConfig;
  TranscodeConfig get transcodeConfig => _transcodeConfig;

  void _ensureInitialized() {
    if (!_initialized) throw StateError('ContentPipelineService.init() must be called before use.');
  }

  Future<ContentPipelineService> init() async {
    _cdnConfig = const CdnConfig();
    _thumbnailConfig = const ThumbnailConfig();
    _transcodeConfig = const TranscodeConfig();
    _initialized = true;
    return this;
  }

  PipelineJob submitUpload({
    required String uploaderId,
    required String fileName,
    required int sizeBytes,
    required String mimeType,
  }) {
    _ensureInitialized();
    if (uploaderId.isEmpty) throw ArgumentError('uploaderId must not be empty');
    if (fileName.isEmpty) throw ArgumentError('fileName must not be empty');
    if (sizeBytes <= 0) throw ArgumentError('sizeBytes must be positive');
    if (mimeType.isEmpty) throw ArgumentError('mimeType must not be empty');
    final id = 'job_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(9999)}';
    final actions = _determineActions(mimeType);

    final job = PipelineJob(
      id: id,
      uploaderId: uploaderId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      currentStage: PipelineStage.upload,
      status: PipelineStatus.queued,
      createdAt: DateTime.now(),
      pendingActions: actions,
    );

    _activeJobs[id] = job;
    _simulateProcessing(id);
    return job;
  }

  PipelineJob? getJob(String jobId) => _activeJobs[jobId];

  List<PipelineJob> getActiveJobs() => _activeJobs.values.toList();

  List<PipelineJob> getCompletedJobs({int limit = 50}) {
    return _completedJobs.take(limit).toList();
  }

  void cancelJob(String jobId) {
    final job = _activeJobs[jobId];
    if (job != null && job.status == PipelineStatus.processing) {
      _activeJobs[jobId] = job.copyWith(
        status: PipelineStatus.cancelled,
        completedAt: DateTime.now(),
      );
    }
  }

  String generateCdnUrl(String fileName, {int? quality}) {
    final q = quality ?? 1080;
    return '${_cdnConfig.baseUrl}/${_cdnConfig.bucketName}/${q}p/$fileName';
  }

  List<String> generateAdaptiveUrls(String fileName) {
    return _cdnConfig.qualityVariants
        .map((q) => generateCdnUrl(fileName, quality: q))
        .toList();
  }

  void submitRemoval(ContentRemovalRequest request) {
    _removalQueue.add(request);
  }

  List<ContentRemovalRequest> getPendingRemovals() => List.from(_removalQueue);

  void processRemoval(String contentId) {
    _removalQueue.removeWhere((r) => r.contentId == contentId);
  }

  MigrationJob startMigration({
    required String sourcePlatform,
    required int totalItems,
  }) {
    final id = 'migration_${_random.nextInt(99999)}';
    final job = MigrationJob(
      id: id,
      sourcePlatform: sourcePlatform,
      totalItems: totalItems,
      processedItems: 0,
      failedItems: 0,
      status: PipelineStatus.processing,
      startedAt: DateTime.now(),
    );
    _migrations[id] = job;
    return job;
  }

  MigrationJob? getMigration(String id) => _migrations[id];

  void updateCdnConfig(CdnConfig config) => _cdnConfig = config;
  void updateThumbnailConfig(ThumbnailConfig config) => _thumbnailConfig = config;
  void updateTranscodeConfig(TranscodeConfig config) => _transcodeConfig = config;

  Map<String, dynamic> getPipelineStats() => {
    'active_jobs': _activeJobs.length,
    'completed_jobs': _completedJobs.length,
    'pending_removals': _removalQueue.length,
    'active_migrations': _migrations.values.where((m) => m.status == PipelineStatus.processing).length,
  };

  List<ProcessingAction> _determineActions(String mimeType) {
    if (mimeType.startsWith('image/')) {
      return [ProcessingAction.resize, ProcessingAction.thumbnail, ProcessingAction.compress];
    }
    if (mimeType.startsWith('video/')) {
      return [ProcessingAction.transcode, ProcessingAction.thumbnail, ProcessingAction.compress];
    }
    if (mimeType.startsWith('audio/')) {
      return [ProcessingAction.transcode, ProcessingAction.compress];
    }
    return [ProcessingAction.compress];
  }

  void _simulateProcessing(String jobId) {
    final stages = PipelineStage.values;
    var currentIndex = 0;

    Future.delayed(const Duration(milliseconds: 100), () {
      _advanceStage(jobId, stages, currentIndex);
    });
  }

  void _advanceStage(String jobId, List<PipelineStage> stages, int index) {
    final job = _activeJobs[jobId];
    if (job == null || job.status == PipelineStatus.cancelled) return;

    if (index >= stages.length) {
      final completed = job.copyWith(
        status: PipelineStatus.completed,
        completedAt: DateTime.now(),
        progress: 1.0,
        pendingActions: [],
        completedActions: job.pendingActions,
      );
      _activeJobs.remove(jobId);
      _completedJobs.insert(0, completed);
      if (_completedJobs.length > 500) _completedJobs.removeLast();
      return;
    }

    _activeJobs[jobId] = job.copyWith(
      currentStage: stages[index],
      status: PipelineStatus.processing,
      progress: index / stages.length,
      stageResults: {
        ...job.stageResults,
        stages[index].name: {
          'started_at': DateTime.now().toIso8601String(),
          'status': 'completed',
        },
      },
    );

    Future.delayed(Duration(milliseconds: 50 + _random.nextInt(100)), () {
      _advanceStage(jobId, stages, index + 1);
    });
  }

  void dispose() {
    _activeJobs.clear();
    _completedJobs.clear();
    _removalQueue.clear();
    _migrations.clear();
  }
}
