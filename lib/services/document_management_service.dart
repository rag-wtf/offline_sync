import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/contextual_retrieval_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/services/embedding_service.dart';
import 'package:offline_sync/services/rag_constants.dart';
import 'package:offline_sync/services/rag_settings_service.dart';
import 'package:offline_sync/services/smart_chunker.dart';
import 'package:offline_sync/services/vector_store.dart';
import 'package:uuid/uuid.dart';

class IngestionProgress {
  const IngestionProgress({
    required this.documentId,
    required this.documentTitle,
    required this.stage,
    this.currentChunk = 0,
    this.totalChunks = 0,
  });

  final String documentId;
  final String documentTitle;
  final String stage; // parsing, chunking, embedding, complete, error
  final int currentChunk;
  final int totalChunks;
}

class IngestionJob {
  IngestionJob({required this.documentId});
  final String documentId;
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  bool get isCancelled => _cancelled;
}

class IngestionResult {
  const IngestionResult({required this.succeeded, required this.failed});

  final List<Document> succeeded;
  final Map<String, String> failed;

  bool get hasErrors => failed.isNotEmpty;
  int get totalCount => succeeded.length + failed.length;
}

class DocumentManagementService {
  final VectorStore _vectorStore = locator<VectorStore>();
  final DocumentParserService _parserService = locator<DocumentParserService>();
  final EmbeddingService _embeddingService = locator<EmbeddingService>();
  final RagSettingsService _settingsService = locator<RagSettingsService>();
  final ContextualRetrievalService _contextualRetrievalService =
      locator<ContextualRetrievalService>();

  final _progressController = StreamController<IngestionProgress>.broadcast();

  // coverage:ignore-start
  Stream<IngestionProgress> get ingestionProgressStream =>
      _progressController.stream;
  // coverage:ignore-end

  // Job management for cancellation
  final Map<String, IngestionJob> _activeJobs = {};
  final Set<String> _inFlightHashes = {};

  static String formatFileSizeMB(double sizeMB) =>
      '${sizeMB.toStringAsFixed(1)} MB';

  Future<IngestionResult> addMultipleDocuments(List<String> filePaths) async {
    final succeeded = <Document>[];
    final failed = <String, String>{};

    for (final filePath in filePaths) {
      try {
        final doc = await addDocument(filePath);
        succeeded.add(doc);
      } on Object catch (e) {
        failed[filePath] = e.toString();
      }
    }
    return IngestionResult(succeeded: succeeded, failed: failed);
  }

  Future<Document> addDocument(
    String filePath, {
    bool skipDuplicateCheck = false,
    bool retainErrorRecord = true,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }

    // 1. Check file size
    final fileSizeMB = (await file.length()) / (1024 * 1024);
    if (fileSizeMB > _settingsService.maxDocumentSizeMB) {
      throw Exception(
        'File size (${formatFileSizeMB(fileSizeMB)}) exceeds limit of '
        '${_settingsService.maxDocumentSizeMB} MB',
      );
    }

    // 2. Calculate Hash for change detection
    final hash = await _calculateFileHash(file);

    if (!skipDuplicateCheck) {
      final existingDoc = _vectorStore.findByHash(hash);
      if (existingDoc != null) {
        return existingDoc;
      }
    }

    if (_inFlightHashes.contains(hash)) {
      // coverage:ignore-line
      // coverage:ignore-start
      throw Exception('This document is already being ingested');
      // coverage:ignore-end
    }
    _inFlightHashes.add(hash);

    final docId = const Uuid().v4();
    final fileName = filePath.split(Platform.pathSeparator).last;
    final overlapChars =
        (RagConstants.maxCharsPerChunk * _settingsService.chunkOverlapPercent)
            .round();

    return _processIngestion(
      docId: docId,
      fileName: fileName,
      filePath: filePath,
      hash: hash,
      parseParams: {'filePath': filePath, 'overlapChars': overlapChars},
      retainErrorRecord: retainErrorRecord,
    );
  }

  Future<Document> addDocumentFromPlatformFile(PlatformFile file) async {
    if (file.path != null) {
      return addDocument(file.path!);
    }

    final length = await file.length();
    final fileSizeMB = length / (1024 * 1024);
    if (fileSizeMB > _settingsService.maxDocumentSizeMB) {
      // coverage:ignore-start
      throw Exception(
        'File size (${formatFileSizeMB(fileSizeMB)}) exceeds limit of '
        '${_settingsService.maxDocumentSizeMB} MB',
      );
      // coverage:ignore-end
    }

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('File content is not available (no path, no bytes)');
    }

    final hash = sha256.convert(bytes).toString();

    final existingDoc = _vectorStore.findByHash(hash);
    if (existingDoc != null) {
      return existingDoc;
    }

    if (_inFlightHashes.contains(hash)) {
      // coverage:ignore-line
      // coverage:ignore-start
      throw Exception('This document is already being ingested');
      // coverage:ignore-end
    }
    _inFlightHashes.add(hash);

    final docId = const Uuid().v4();
    final overlapChars =
        (RagConstants.maxCharsPerChunk * _settingsService.chunkOverlapPercent)
            .round();

    return _processIngestion(
      docId: docId,
      fileName: file.name,
      filePath: file.path, // May be null on web, which is fine
      hash: hash,
      parseParams: {
        'bytes': bytes,
        'fileName': file.name,
        'overlapChars': overlapChars,
      },
    );
  }

  Future<Document> _processIngestion({
    required String docId,
    required String fileName,
    required String? filePath,
    required String hash,
    required Map<String, dynamic> parseParams,
    bool persistDocument = true,
    bool retainErrorRecord = true,
  }) async {
    final job = IngestionJob(documentId: docId);
    _activeJobs[docId] = job;

    final activeEmbeddingModelId = _settingsService.activeEmbeddingModelId;
    if (activeEmbeddingModelId == null) {
      _activeJobs.remove(docId);
      _inFlightHashes.remove(hash);
      throw StateError('No active embedding model is available');
    }
    final contextualRetrievalEnabled =
        _settingsService.contextualRetrievalEnabled;

    // Initial record
    var doc = Document(
      id: docId,
      title: fileName,
      filePath: filePath ?? fileName, // Fallback to name if path missing
      format: _parserService.detectFormat(fileName),
      chunkCount: 0,
      totalCharacters: 0,
      contentHash: hash,
      ingestedAt: DateTime.now(),
      status: IngestionStatus.processing,
      contextualRetrievalEnabled: contextualRetrievalEnabled,
      embeddingModelId: activeEmbeddingModelId,
    );
    try {
      if (persistDocument) _vectorStore.insertDocument(doc);
      _emitProgress(docId, fileName, 'parsing');

      if (job.isCancelled) throw Exception('Ingestion cancelled');

      // 3. Parse & Chunk (in Isolate)
      final parseResult = await compute(_parseAndChunk, parseParams);

      if (job.isCancelled) throw Exception('Ingestion cancelled');

      final content = parseResult['content'] as String;
      final chunks = parseResult['chunks'] as List<String>;
      final title = parseResult['title'] as String;
      final format = parseResult['format'] as DocumentFormat;

      // 4. Contextual Retrieval (if enabled)
      var chunksToEmbed = chunks;
      var contextMetadata = <Map<String, Object>>[];

      if (contextualRetrievalEnabled) {
        // coverage:ignore-start
        _emitProgress(docId, fileName, 'contextualizing', 0, chunks.length);
        // coverage:ignore-end

        // coverage:ignore-start
        if (await _contextualRetrievalService.isSupported) {
          final contextualized = await _contextualRetrievalService
              .contextualizeDocument(
                documentContent: content,
                chunks: chunks,
                onProgress: (current, total) {
                  if (job.isCancelled) throw Exception('Ingestion cancelled');
                  _emitProgress(
                    docId,
                    fileName,
                    'contextualizing',
                    current,
                    total,
                  );
                },
              );

          chunksToEmbed = contextualized.map((c) => c.combinedContent).toList();
          contextMetadata = contextualized
              .map(
                (c) => <String, Object>{
                  'context': c.context,
                  'originalContent': c.originalContent,
                },
              )
              .toList();
        }
        // coverage:ignore-end
      }

      _emitProgress(docId, fileName, 'embedding', 0, chunksToEmbed.length);

      // 5. Embed & Store in batches of 10 to avoid high memory watermark.
      // Embedding backends are stateful; pin the model and serialize calls.
      const batchSize = 10;

      for (var i = 0; i < chunksToEmbed.length; i += batchSize) {
        if (job.isCancelled) {
          throw Exception('Ingestion cancelled'); // coverage:ignore-line
        }

        // coverage:ignore-start
        final end = (i + batchSize < chunksToEmbed.length)
            ? i + batchSize
            : chunksToEmbed.length;
        // coverage:ignore-end
        final batch = chunksToEmbed.sublist(i, end);

        final batchResults = <EmbeddingData>[];
        for (final entry in batch.asMap().entries) {
          if (_settingsService.activeEmbeddingModelId !=
              activeEmbeddingModelId) {
            throw StateError('Embedding model changed during ingestion');
          }
          final localIndex = entry.key;
          final chunkContent = entry.value;
          final globalIndex = i + localIndex;

          final embedding = await _embeddingService.generateEmbedding(
            chunkContent,
          );

          final metadata = {
            'documentId': docId,
            'documentTitle': title,
            'documentPath': filePath ?? fileName,
            // coverage:ignore-start
            'seq': globalIndex,
            'totalChunks': chunks.length,
            // coverage:ignore-end
          };

          // coverage:ignore-start
          if (contextMetadata.isNotEmpty &&
              globalIndex < contextMetadata.length) {
            metadata.addAll(contextMetadata[globalIndex]);
          }
          // coverage:ignore-end

          batchResults.add(
            EmbeddingData(
              id: const Uuid().v4(),
              documentId: docId,
              content: chunkContent,
              embedding: embedding,
              metadata: metadata,
              embeddingModelId: activeEmbeddingModelId,
            ),
          );
        }

        if (_settingsService.activeEmbeddingModelId != activeEmbeddingModelId) {
          throw StateError('Embedding model changed during ingestion');
        }
        _vectorStore.insertEmbeddingsBatch(batchResults);

        _emitProgress(docId, fileName, 'embedding', end, chunks.length);
      }

      // 6. Update Document Status
      doc = Document(
        id: docId,
        title: title,
        filePath: filePath ?? fileName,
        format: format,
        chunkCount: chunks.length,
        totalCharacters: content.length,
        contentHash: hash,
        ingestedAt: DateTime.now(),
        status: IngestionStatus.complete,
        contextualRetrievalEnabled: contextualRetrievalEnabled,
        embeddingModelId: activeEmbeddingModelId,
      );
      if (persistDocument) _vectorStore.updateDocument(doc);
      _emitProgress(docId, fileName, 'complete', chunks.length, chunks.length);

      return doc;
    } on Object catch (error) {
      final status = job.isCancelled
          ? IngestionStatus.cancelled
          : IngestionStatus.error;
      final msg = job.isCancelled ? 'Cancelled' : error.toString();

      final errorDoc = Document(
        id: docId,
        title: fileName,
        filePath: filePath ?? fileName,
        format: doc.format,
        chunkCount: 0,
        totalCharacters: 0,
        contentHash: hash,
        ingestedAt: DateTime.now(),
        status: status,
        contextualRetrievalEnabled: contextualRetrievalEnabled,
        embeddingModelId: activeEmbeddingModelId,
        errorMessage: msg,
      );
      try {
        _vectorStore.deleteVectorsForDocument(docId);
      } on Object catch (_) {
        // Best-effort cleanup; do not hide the original ingestion failure.
      }
      if (persistDocument && retainErrorRecord) {
        try {
          _vectorStore.updateDocument(errorDoc);
        } on Object catch (_) {
          // Preserve the original ingestion failure if error bookkeeping fails.
        }
      }
      if (persistDocument && !retainErrorRecord) {
        try {
          _vectorStore.deleteDocument(docId);
        } on Object catch (_) {
          // The source record may not have been inserted; keep the original
          // ingestion error when cleanup cannot complete.
        }
      }
      _emitProgress(docId, fileName, 'error');
      rethrow;
    } finally {
      _activeJobs.remove(docId);
      _inFlightHashes.remove(hash);
    }
  }

  Future<Document?> refreshDocument(String documentId) async {
    final oldDoc = _vectorStore.getDocument(documentId);
    if (oldDoc == null) return null;

    if (!_hasSourceFile(oldDoc)) {
      return oldDoc;
    }

    // Avoid re-ingesting an unchanged file. This also prevents the UNIQUE
    // content-hash index from turning a harmless refresh into an error record.
    final sourceFile = File(oldDoc.filePath);
    final currentHash = await _calculateFileHash(sourceFile);
    if (currentHash == oldDoc.contentHash) {
      return oldDoc;
    }

    return _reindexExistingDocument(oldDoc, currentHash);
  }

  bool _hasSourceFile(Document document) {
    return File(document.filePath).existsSync();
  }

  bool hasSourceForReindex(Document document) => _hasSourceFile(document);

  Future<void> deleteDocument(String documentId) async {
    _vectorStore.deleteDocument(documentId);
  }

  Future<void> renameDocument(String documentId, String title) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title', 'Document title is required');
    }

    final document = _vectorStore.getDocument(documentId);
    if (document == null) {
      throw StateError('Document not found');
    }

    _vectorStore.renameDocument(documentId, normalizedTitle);
  }

  Future<Document?> reindexDocument(String documentId) async {
    final oldDocument = _vectorStore.getDocument(documentId);
    if (oldDocument == null || !_hasSourceFile(oldDocument)) return oldDocument;

    final sourceFile = File(oldDocument.filePath);
    final hash = await _calculateFileHash(sourceFile);
    return _reindexExistingDocument(oldDocument, hash);
  }

  Future<Document> _reindexExistingDocument(
    Document oldDocument,
    String hash,
  ) async {
    if (_inFlightHashes.contains(hash)) {
      throw StateError('This document is already being ingested');
    }

    _inFlightHashes.add(hash);
    try {
      final overlapChars =
          (RagConstants.maxCharsPerChunk * _settingsService.chunkOverlapPercent)
              .round();
      final stagedId = const Uuid().v4();
      final staged = await _processIngestion(
        docId: stagedId,
        fileName: oldDocument.title,
        filePath: oldDocument.filePath,
        hash: hash,
        parseParams: {
          'filePath': oldDocument.filePath,
          'overlapChars': overlapChars,
        },
        persistDocument: false,
        retainErrorRecord: false,
      );
      final replacement = Document(
        id: oldDocument.id,
        title: staged.title,
        filePath: staged.filePath,
        format: staged.format,
        chunkCount: staged.chunkCount,
        totalCharacters: staged.totalCharacters,
        contentHash: staged.contentHash,
        ingestedAt: staged.ingestedAt,
        status: staged.status,
        contextualRetrievalEnabled: staged.contextualRetrievalEnabled,
        embeddingModelId: staged.embeddingModelId,
      );
      _vectorStore.replaceDocument(
        oldDocumentId: oldDocument.id,
        stagedDocumentId: staged.id,
        replacement: replacement,
      );
      return replacement;
    } on Object {
      _inFlightHashes.remove(hash);
      rethrow;
    }
  }

  Future<List<Document>> getAllDocuments() async {
    return _vectorStore.getAllDocuments();
  }

  // coverage:ignore-start
  Future<void> deleteAllDocuments() async {
    _vectorStore.deleteAllDocuments();
  }
  // coverage:ignore-end

  // coverage:ignore-start
  Future<bool> hasDocumentChanged(String documentId) async {
    final doc = _vectorStore.getDocument(documentId);
    if (doc == null) return false;

    final file = File(doc.filePath);
    if (!file.existsSync()) return true;

    final currentHash = await _calculateFileHash(file);
    return currentHash != doc.contentHash;
  }
  // coverage:ignore-end

  Future<Document?> findByHash(String contentHash) async {
    return _vectorStore.findByHash(contentHash);
  }

  Future<List<EmbeddingData>> getDocumentChunks(String documentId) async {
    return _vectorStore.getChunksForDocument(documentId);
  }

  Future<void> optimizeDatabase() async {
    _vectorStore.optimizeDatabase();
  }

  // coverage:ignore-start
  void cancelIngestion(String documentId) {
    _activeJobs[documentId]?.cancel();
  }
  // coverage:ignore-end

  Future<String> _calculateFileHash(File file) async {
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  void _emitProgress(
    String docId,
    String title,
    String stage, [
    int current = 0,
    int total = 0,
  ]) {
    _progressController.add(
      IngestionProgress(
        documentId: docId,
        documentTitle: title,
        stage: stage,
        currentChunk: current,
        totalChunks: total,
      ),
    );
  }
}

Future<Map<String, dynamic>> _parseAndChunk(Map<String, dynamic> params) async {
  final parser = DocumentParserService();
  final chunker = SmartChunker();

  ParsedDocument parsed;
  if (params.containsKey('bytes')) {
    final bytes = params['bytes'] as Uint8List;
    final fileName = params['fileName'] as String;
    parsed = await parser.parseDocumentFromBytes(bytes, fileName);
  } else {
    final filePath = params['filePath'] as String;
    parsed = await parser.parseDocument(filePath);
  }

  final overlapChars = params['overlapChars'] as int? ?? 50;
  final chunks = chunker.chunk(parsed.content, overlapChars: overlapChars);

  return {
    'content': parsed.content,
    'chunks': chunks,
    'title': parsed.title,
    'format': parsed.format,
  };
}
