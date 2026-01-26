import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:offline_sync/app/app.locator.dart';
import 'package:offline_sync/models/document.dart';
import 'package:offline_sync/services/contextual_retrieval_service.dart';
import 'package:offline_sync/services/document_parser_service.dart';
import 'package:offline_sync/services/embedding_service.dart';
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
  const IngestionResult({
    required this.succeeded,
    required this.failed,
  });

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

  Stream<IngestionProgress> get ingestionProgressStream =>
      _progressController.stream;

  // Job management for cancellation
  final Map<String, IngestionJob> _activeJobs = {};

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
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }

    // 1. Check file size
    final fileSizeMB = (await file.length()) / (1024 * 1024);
    if (fileSizeMB > _settingsService.maxDocumentSizeMB) {
      throw Exception(
        'File size ($fileSizeMB MB) exceeds limit of '
        '${_settingsService.maxDocumentSizeMB} MB',
      );
    }

    // 2. Calculate Hash for change detection
    final hash = await _calculateFileHash(file);

    if (!skipDuplicateCheck) {
      final existingDoc = await _vectorStore.findByHash(hash);
      if (existingDoc != null) {
        return existingDoc;
      }
    }

    final docId = const Uuid().v4();
    final fileName = filePath.split(Platform.pathSeparator).last;

    return _processIngestion(
      docId: docId,
      fileName: fileName,
      filePath: filePath,
      hash: hash,
      parseParams: {'filePath': filePath},
    );
  }

  Future<Document> addDocumentFromPlatformFile(PlatformFile file) async {
    if (file.bytes == null) {
      if (file.path != null) {
        return addDocument(file.path!);
      }
      throw Exception('File content is not available (no path, no bytes)');
    }

    // Byte-based ingestion (Web or generic)
    final bytes = file.bytes!;
    final fileSizeMB = bytes.length / (1024 * 1024);
    if (fileSizeMB > _settingsService.maxDocumentSizeMB) {
      throw Exception(
        'File size ($fileSizeMB MB) exceeds limit of '
        '${_settingsService.maxDocumentSizeMB} MB',
      );
    }

    final hash = sha256.convert(bytes).toString();

    final existingDoc = await _vectorStore.findByHash(hash);
    if (existingDoc != null) {
      return existingDoc;
    }

    final docId = const Uuid().v4();

    return _processIngestion(
      docId: docId,
      fileName: file.name,
      filePath: file.path, // May be null on web, which is fine
      hash: hash,
      parseParams: {
        'bytes': bytes,
        'fileName': file.name,
      },
    );
  }

  Future<Document> _processIngestion({
    required String docId,
    required String fileName,
    required String? filePath,
    required String hash,
    required Map<String, dynamic> parseParams,
  }) async {
    final job = IngestionJob(documentId: docId);
    _activeJobs[docId] = job;

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
      contextualRetrievalEnabled: _settingsService.contextualRetrievalEnabled,
    );
    _vectorStore.insertDocument(doc);
    _emitProgress(docId, fileName, 'parsing');

    try {
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

      if (_settingsService.contextualRetrievalEnabled) {
        _emitProgress(docId, fileName, 'contextualizing', 0, chunks.length);

        if (await _contextualRetrievalService.isSupported) {
          final contextualized =
              await _contextualRetrievalService.contextualizeDocument(
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
      }

      _emitProgress(docId, fileName, 'embedding', 0, chunksToEmbed.length);

      // 5. Embed & Store
      final embeddingDataList = <EmbeddingData>[];
      const batchSize = 10;

      for (var i = 0; i < chunksToEmbed.length; i += batchSize) {
        if (job.isCancelled) throw Exception('Ingestion cancelled');

        final end = (i + batchSize < chunksToEmbed.length)
            ? i + batchSize
            : chunksToEmbed.length;
        final batch = chunksToEmbed.sublist(i, end);

        final futures = batch.asMap().entries.map((entry) async {
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
            'seq': globalIndex,
            'totalChunks': chunks.length,
          };

          if (contextMetadata.isNotEmpty &&
              globalIndex < contextMetadata.length) {
            metadata.addAll(contextMetadata[globalIndex]);
          }

          return EmbeddingData(
            id: const Uuid().v4(),
            documentId: docId,
            content: chunkContent,
            embedding: embedding,
            metadata: metadata,
          );
        });

        final batchResults = await Future.wait(futures);
        embeddingDataList.addAll(batchResults);

        _emitProgress(docId, fileName, 'embedding', end, chunks.length);
      }

      // Store in DB
      _vectorStore.insertEmbeddingsBatch(embeddingDataList);

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
        contextualRetrievalEnabled: _settingsService.contextualRetrievalEnabled,
      );
      _vectorStore.updateDocument(doc);
      _emitProgress(docId, fileName, 'complete', chunks.length, chunks.length);

      return doc;
    } catch (e) {
      final status = job.isCancelled
          ? IngestionStatus.cancelled
          : IngestionStatus.error;
      final msg = job.isCancelled ? 'Cancelled' : e.toString();

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
        errorMessage: msg,
      );
      _vectorStore.updateDocument(errorDoc);
      _emitProgress(docId, fileName, 'error');
      rethrow;
    } finally {
      _activeJobs.remove(docId);
    }
  }

  Future<Document?> refreshDocument(String documentId) async {
    final oldDoc = _vectorStore.getDocument(documentId);
    if (oldDoc == null) return null;

    final file = File(oldDoc.filePath);
    if (!file.existsSync()) {
      throw const FileSystemException('Original file not found');
    }

    final newHash = await _calculateFileHash(file);
    if (newHash == oldDoc.contentHash &&
        oldDoc.status == IngestionStatus.complete) {
      return oldDoc;
    }

    _vectorStore.deleteDocument(documentId);
    return addDocument(oldDoc.filePath, skipDuplicateCheck: true);
  }

  Future<void> deleteDocument(String documentId) async {
    _vectorStore.deleteDocument(documentId);
  }

  Future<List<Document>> getAllDocuments() async {
    return _vectorStore.getAllDocuments();
  }

  Future<void> deleteAllDocuments() async {
    final docs = await getAllDocuments();
    for (final doc in docs) {
      await deleteDocument(doc.id);
    }
  }

  Future<bool> hasDocumentChanged(String documentId) async {
    final doc = _vectorStore.getDocument(documentId);
    if (doc == null) return false;

    final file = File(doc.filePath);
    if (!file.existsSync()) return true;

    final currentHash = await _calculateFileHash(file);
    return currentHash != doc.contentHash;
  }

  Future<Document?> findByHash(String contentHash) async {
    return _vectorStore.findByHash(contentHash);
  }

  Future<List<EmbeddingData>> getDocumentChunks(String documentId) async {
    return _vectorStore.getChunksForDocument(documentId);
  }

  Future<void> optimizeDatabase() async {
    _vectorStore.optimizeDatabase();
  }

  void cancelIngestion(String documentId) {
    _activeJobs[documentId]?.cancel();
  }

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

Future<Map<String, dynamic>> _parseAndChunk(
    Map<String, dynamic> params,
) async {
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

  final chunks = chunker.chunk(parsed.content);

  return {
    'content': parsed.content,
    'chunks': chunks,
    'title': parsed.title,
    'format': parsed.format,
  };
}
