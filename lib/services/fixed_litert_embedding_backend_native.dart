import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_gemma/core/model_management/model_specs.dart'
    show EmbeddingModelSpec;
import 'package:flutter_gemma/core/registry/embedding_backend_provider.dart';
import 'package:flutter_gemma/core/registry/runtime_config.dart';
import 'package:flutter_gemma/core/utils/gemma_log.dart';
import 'package:flutter_gemma/flutter_gemma_interface.dart'
    show EmbeddingModel;
import 'package:flutter_gemma_embeddings/embedding_tokenizer.dart'
    show loadGemmaSentencePieceEmbeddingTokenizer;
import 'package:flutter_gemma_embeddings/flutter_gemma_embeddings.dart'
    show
        CommonEmbeddingModel,
        EmbeddingForwardPass,
        EmbeddingOutputContract,
        ForwardPassDescriptor,
        ForwardResult;
import 'package:flutter_gemma_litertlm/litert_bindings.dart';

/// Top-level factory tear-off for isolate serialization.
EmbeddingForwardPass createFixedLiteRtEmbeddingForwardPass(String modelPath) =>
    FixedLiteRtEmbeddingForwardPass(modelPath);

/// LiteRT C API embedding backend that uses [LiteRtLayoutPosix] and
/// [LiteRtRankedTensorTypePosix] unconditionally on native platforms.
///
/// Upstream flutter_gemma_litertlm uses MSVC struct packing on Windows,
/// but Google compiles the LiteRT shared library using Clang (Bazel LLVM),
/// causing an artificial 4-byte padding offset that leads to seqLen=0, dim=0
/// and CreateTensorBufferFromHostMemory failures.
class FixedLiteRtEmbeddingBackend implements EmbeddingBackendProvider {
  const FixedLiteRtEmbeddingBackend();

  @override
  String get name => 'LiteRT Embedding';

  @override
  int get priority => 0;

  @override
  bool canHandle(EmbeddingModelSpec spec) => true;

  @override
  Future<EmbeddingModel> createModel(
    EmbeddingModelSpec spec,
    RuntimeConfig config,
  ) async {
    final tokenizerPath = config.tokenizerPath;
    if (tokenizerPath == null) {
      throw StateError(
        'FixedLiteRtEmbeddingBackend requires config.tokenizerPath '
        '(resolved by core from the active embedding model).',
      );
    }
    return CommonEmbeddingModel.create(
      descriptor: ForwardPassDescriptor(
        engineTag: 'LiteRT',
        modelPath: config.modelPath,
        factory: createFixedLiteRtEmbeddingForwardPass,
        tokenizerFactory: loadGemmaSentencePieceEmbeddingTokenizer,
        outputContract: EmbeddingOutputContract.pooledFinal,
      ),
      tokenizerPath: tokenizerPath,
      onClose: () {},
    );
  }
}

class FixedLiteRtEmbeddingForwardPass implements EmbeddingForwardPass {
  FixedLiteRtEmbeddingForwardPass(
    this._modelPath, {
    int? inputSequenceLength,
    int? outputDimension,
  }) : _pinnedSeqLen = inputSequenceLength,
       _pinnedDim = outputDimension;

  final String _modelPath;
  final int? _pinnedSeqLen;
  final int? _pinnedDim;

  LiteRtBindings? _bindings;
  LiteRtEnvironment? _environment;
  LiteRtModel? _model;
  LiteRtOptions? _options;
  LiteRtCompiledModel? _compiledModel;

  int? _inputSequenceLength;
  int? _outputDimension;
  bool _disposed = false;

  @override
  int get outputDimension {
    final dim = _outputDimension;
    if (dim == null) {
      throw StateError(
        'FixedLiteRtEmbeddingForwardPass.load() has not completed',
      );
    }
    return dim;
  }

  @override
  int? get inputSequenceLength => _inputSequenceLength;

  @override
  EmbeddingOutputContract? get outputContract => null;

  @override
  Future<void> load() async {
    final bindings = LiteRtBindings.open();
    _bindings = bindings;

    LiteRtEnvironment? environment;
    LiteRtModel? model;
    LiteRtOptions? options;
    LiteRtCompiledModel? compiled;
    try {
      final envPtr = calloc<LiteRtEnvironment>();
      bindings
          .createEnvironment(0, nullptr, envPtr)
          .check('LiteRtCreateEnvironment');
      environment = envPtr.value;
      calloc.free(envPtr);

      final pathC = _modelPath.toNativeUtf8();
      final modelPtr = calloc<LiteRtModel>();
      try {
        bindings
            .createModelFromFile(environment, pathC, modelPtr)
            .check('LiteRtCreateModelFromFile($_modelPath)');
      } finally {
        calloc.free(pathC);
      }
      model = modelPtr.value;
      calloc.free(modelPtr);

      final optsPtr = calloc<LiteRtOptions>();
      bindings.createOptions(optsPtr).check('LiteRtCreateOptions');
      options = optsPtr.value;
      calloc.free(optsPtr);
      bindings
          .setOptionsHardwareAccelerators(options, kLiteRtHwAcceleratorCpu)
          .check('LiteRtSetOptionsHardwareAccelerators');

      final compiledPtr = calloc<LiteRtCompiledModel>();
      bindings
          .createCompiledModel(environment, model, options, compiledPtr)
          .check('LiteRtCreateCompiledModel');
      compiled = compiledPtr.value;
      calloc.free(compiledPtr);

      int seqLen;
      int dim;
      if (_pinnedSeqLen == null) {
        final inLayout = calloc<LiteRtLayoutPosix>();
        try {
          bindings
              .getInputTensorLayout(compiled, 0, 0, inLayout.cast<Void>())
              .check('LiteRtGetCompiledModelInputTensorLayout');
          final rank = inLayout.ref.rankAndHasStrides & 0x7f;
          if (rank < 2) {
            throw StateError(
              'Embedding model input has rank=$rank, expected >=2',
            );
          }
          seqLen = inLayout.ref.dimensions[1];
        } finally {
          calloc.free(inLayout);
        }
      } else {
        seqLen = _pinnedSeqLen;
      }

      if (_pinnedDim == null) {
        final outLayouts = calloc<LiteRtLayoutPosix>();
        try {
          bindings
              .getOutputTensorLayouts(
                compiled,
                0,
                1,
                outLayouts.cast<Void>(),
                false,
              )
              .check('LiteRtGetCompiledModelOutputTensorLayouts');
          final rank = outLayouts.ref.rankAndHasStrides & 0x7f;
          if (rank < 2) {
            throw StateError(
              'Embedding model output has rank=$rank, expected >=2',
            );
          }
          dim = outLayouts.ref.dimensions[1];
        } finally {
          calloc.free(outLayouts);
        }
      } else {
        dim = _pinnedDim;
      }

      gemmaLog(
        '[FixedLiteRtEmbeddingForwardPass] loaded: seqLen=$seqLen, dim=$dim',
      );

      _environment = environment;
      _model = model;
      _options = options;
      _compiledModel = compiled;
      _inputSequenceLength = seqLen;
      _outputDimension = dim;
    } catch (_) {
      if (compiled != null) bindings.destroyCompiledModel(compiled);
      if (options != null) bindings.destroyOptions(options);
      if (model != null) bindings.destroyModel(model);
      if (environment != null) bindings.destroyEnvironment(environment);
      rethrow;
    }
  }

  @override
  Future<ForwardResult> run({
    required List<int> tokenIds,
    List<int>? attentionMask,
    List<int>? tokenTypeIds,
  }) async {
    if (_disposed) {
      throw StateError('FixedLiteRtEmbeddingForwardPass is disposed');
    }
    if (_outputDimension == null) {
      throw StateError(
        'FixedLiteRtEmbeddingForwardPass.run() called before load() completed',
      );
    }
    final values = _runForward(tokenIds);
    return ForwardResult(values: values, shape: [1, outputDimension]);
  }

  List<double> _runForward(List<int> tokens) {
    final bindings = _bindings!;
    final seq = inputSequenceLength!;
    final dim = outputDimension;

    final inType = calloc<LiteRtRankedTensorTypePosix>();
    inType.ref.elementType = kLiteRtElementTypeInt32;
    inType.ref.layout.rankAndHasStrides = 2 & 0x7f;
    inType.ref.layout.dimensions[0] = 1;
    inType.ref.layout.dimensions[1] = seq;

    final inAlloc = allocAligned(seq * 4);
    final inBufPtr = calloc<LiteRtTensorBuffer>();

    final outType = calloc<LiteRtRankedTensorTypePosix>();
    outType.ref.elementType = kLiteRtElementTypeFloat32;
    outType.ref.layout.rankAndHasStrides = 2 & 0x7f;
    outType.ref.layout.dimensions[0] = 1;
    outType.ref.layout.dimensions[1] = dim;

    final outAlloc = allocAligned(dim * 4);
    final outBufPtr = calloc<LiteRtTensorBuffer>();
    var inBufCreated = false;
    var outBufCreated = false;

    try {
      final inHost = inAlloc.aligned.cast<Int32>();
      for (var i = 0; i < seq; i++) {
        inHost[i] = i < tokens.length ? tokens[i] : 0;
      }

      bindings
          .createTensorBufferFromHostMemory(
            inType.cast<Void>(),
            inAlloc.aligned.cast(),
            seq * 4,
            nullptr,
            inBufPtr,
          )
          .check('CreateTensorBufferFromHostMemory(input)');
      inBufCreated = true;

      bindings
          .createTensorBufferFromHostMemory(
            outType.cast<Void>(),
            outAlloc.aligned.cast(),
            dim * 4,
            nullptr,
            outBufPtr,
          )
          .check('CreateTensorBufferFromHostMemory(output)');
      outBufCreated = true;

      bindings
          .runCompiledModel(_compiledModel!, 0, 1, inBufPtr, 1, outBufPtr)
          .check('LiteRtRunCompiledModel');

      final lockedPtr = calloc<Pointer<Void>>();
      try {
        bindings
            .lockTensorBuffer(
              outBufPtr.value,
              lockedPtr,
              kLiteRtTensorBufferLockModeRead,
            )
            .check('LiteRtLockTensorBuffer(output)');
        final outFloat = lockedPtr.value.cast<Float>();
        final result = List<double>.generate(dim, (i) => outFloat[i]);
        bindings.unlockTensorBuffer(outBufPtr.value);
        return result;
      } finally {
        calloc.free(lockedPtr);
      }
    } finally {
      if (inBufCreated) bindings.destroyTensorBuffer(inBufPtr.value);
      if (outBufCreated) bindings.destroyTensorBuffer(outBufPtr.value);
      calloc
        ..free(inBufPtr)
        ..free(outBufPtr)
        ..free(inAlloc.raw)
        ..free(outAlloc.raw)
        ..free(inType)
        ..free(outType);
    }
  }

  @override
  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;
    final bindings = _bindings;
    if (bindings == null) return;
    if (_compiledModel != null) bindings.destroyCompiledModel(_compiledModel!);
    if (_options != null) bindings.destroyOptions(_options!);
    if (_model != null) bindings.destroyModel(_model!);
    if (_environment != null) bindings.destroyEnvironment(_environment!);
  }
}
