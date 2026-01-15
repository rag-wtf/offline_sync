# Device-Capability Model Selection

Auto-select optimal inference and embedding models based on device RAM, storage, and GPU availability. Allow users to manually switch models in settings. Implements dynamic model loading/unloading to optimize memory usage on low-end devices.

## Minimum System Requirements

| Component | Min RAM | Min Storage | Total |
|-----------|---------|-------------|-------|
| Inference (Gemma 270M) | ~600MB | 300MB | — |
| Embedding (Gecko 64) | ~200MB | 110MB | — |
| **Combined Minimum** | **~800MB** | **~500MB** | **~1.3GB** |

> [!CAUTION]
> Devices with <2GB RAM or <1GB free storage will show an **"Unsupported Device"** message with graceful degradation options.

---

## Proposed Changes

### Device Detection Layer

#### [NEW] [device_capability_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/device_capability_service.dart)

Service to detect device capabilities using `device_info_plus` and `system_info_plus`:

```dart
class DeviceCapabilities {
  final int totalRamMB;
  final int availableStorageMB;
  final bool hasGpu;
  final String platform; // android, ios, web, linux, macos, windows
}

class DeviceCapabilityService {
  Future<DeviceCapabilities> getCapabilities();
}
```

---

### Model Recommendation Layer

#### [NEW] [model_recommendation_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/model_recommendation_service.dart)

Service to recommend optimal models based on device capabilities:

| Device Tier | RAM | Storage | Inference Model | Embedding Model |
|-------------|-----|---------|-----------------|-----------------|
| **Low** | <4GB | <2GB | Gemma 3 270M (0.3GB) | Gecko 64 (110MB) |
| **Mid** | 4-8GB | 2-4GB | Gemma 3 1B (0.5GB) | EmbeddingGemma 256 (179MB) |
| **High** | >8GB | >4GB | Gemma 3n E2B (3.1GB) | EmbeddingGemma 512 (179MB) |
| **Premium** | >12GB+GPU | >8GB | Gemma 3n E4B (6.5GB) | EmbeddingGemma 1024 (183MB) |

```dart
class ModelRecommendationService {
  /// Check if device meets minimum requirements
  bool meetsMinimumRequirements(DeviceCapabilities capabilities);
  
  /// Get user-friendly message for unsupported devices
  String getUnsupportedDeviceMessage(DeviceCapabilities capabilities);
  
  RecommendedModels getRecommendedModels(DeviceCapabilities capabilities);
  List<InferenceModelDefinition> getCompatibleInferenceModels(DeviceCapabilities capabilities);
  List<EmbeddingModelDefinition> getCompatibleEmbeddingModels(DeviceCapabilities capabilities);
}
```

---

### Memory-Efficient Model Loading

#### [NEW] [model_loader_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/model_loader_service.dart)

For **low-end devices** (RAM <4GB), only one model is loaded at a time. Models are loaded/unloaded dynamically:

```dart
enum LoadedModelType { none, inference, embedding }

class ModelLoaderService {
  LoadedModelType _currentlyLoaded = LoadedModelType.none;
  
  /// Load inference model, unloading embedding if loaded
  Future<void> loadInferenceModel();
  
  /// Load embedding model, unloading inference if loaded
  Future<void> loadEmbeddingModel();
  
  /// Unload current model to free memory
  Future<void> unloadCurrentModel();
  
  /// Check which model is currently loaded
  LoadedModelType get currentlyLoaded;
}
```

**Flow for low-end devices:**
1. **Index documents** → Load embedding model → Generate vectors → Unload
2. **Chat query** → Load embedding model → Get query vector → Unload → Load inference model → Generate response → Keep loaded for next query

**Flow for high-end devices (RAM ≥4GB):**
- Both models remain loaded simultaneously for instant responses

---

### Unsupported Device Handling

#### [NEW] [unsupported_device_view.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/ui/views/unsupported_device/unsupported_device_view.dart)

User-friendly screen shown when device doesn't meet minimum requirements:

```
┌─────────────────────────────────────┐
│         ⚠️ Device Limitations       │
├─────────────────────────────────────┤
│                                     │
│  Your device has limited resources  │
│  for on-device AI:                  │
│                                     │
│  • RAM: 1.5GB (need 2GB minimum)    │
│  • Storage: 800MB free              │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Options:                           │
│                                     │
│  [Continue Anyway (Slower)]         │
│  - Uses smallest models             │
│  - May experience delays            │
│                                     │
│  [Free Up Storage]                  │
│  - Opens device settings            │
│                                     │
└─────────────────────────────────────┘
```

---

### Model Configuration Expansion

#### [MODIFY] [model_config.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/model_config.dart)

Expand with full model catalog from `edge_ai/lib/models/`:

```diff
+/// Device tier for model selection
+enum DeviceTier { low, mid, high, premium }

 class ModelDefinition {
   const ModelDefinition({
     required this.id,
     required this.name,
     required this.modelUrl,
     required this.type,
     this.tokenizerUrl,
     this.sha256,
+    required this.sizeBytes,
+    required this.minRamMB,
+    required this.requiresGpu,
+    required this.tier,
   });
   // ... fields
 }

+/// Full inference model catalog
+class InferenceModels {
+  static const gemma3_270M = ModelDefinition(...);
+  static const gemma3_1B = ModelDefinition(...);
+  static const gemma3n_2B = ModelDefinition(...);
+  // ... all models from edge_ai/lib/models/model.dart
+}

+/// Full embedding model catalog  
+class EmbeddingModels {
+  static const gecko64 = ModelDefinition(...);
+  static const embeddingGemma256 = ModelDefinition(...);
+  // ... all models from edge_ai/lib/models/embedding_model.dart
+}
```

---

### Model Management Updates

#### [MODIFY] [model_management_service.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/services/model_management_service.dart)

Add methods for switching models:

```diff
 class ModelManagementService {
+  ModelDefinition? _activeInferenceModel;
+  ModelDefinition? _activeEmbeddingModel;
+
+  ModelDefinition? get activeInferenceModel => _activeInferenceModel;
+  ModelDefinition? get activeEmbeddingModel => _activeEmbeddingModel;
+
+  /// Switch to a different inference model
+  Future<void> switchInferenceModel(ModelDefinition model);
+
+  /// Switch to a different embedding model  
+  Future<void> switchEmbeddingModel(ModelDefinition model);
+
+  /// Get list of downloaded models
+  List<ModelDefinition> get downloadedModels;
 }
```

---

### Settings UI Enhancement

#### [MODIFY] [settings_viewmodel.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/ui/views/settings/settings_viewmodel.dart)

Add model selection capabilities:

```diff
 class SettingsViewModel extends BaseViewModel {
+  final DeviceCapabilityService _deviceService;
+  final ModelRecommendationService _recommendationService;
+
+  DeviceCapabilities? _capabilities;
+  List<ModelDefinition> _compatibleInferenceModels = [];
+  List<ModelDefinition> _compatibleEmbeddingModels = [];
+
+  ModelDefinition? get activeInferenceModel;
+  ModelDefinition? get activeEmbeddingModel;
+
+  Future<void> switchInferenceModel(ModelDefinition model);
+  Future<void> switchEmbeddingModel(ModelDefinition model);
 }
```

#### [MODIFY] [settings_view.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/ui/views/settings/settings_view.dart)

Redesign with sections:

```
┌─────────────────────────────────────┐
│ Settings                            │
├─────────────────────────────────────┤
│ 📱 DEVICE INFO                      │
│ RAM: 8GB | Storage: 12GB free       │
│ Tier: High                          │
├─────────────────────────────────────┤
│ 🤖 INFERENCE MODEL                  │
│ ┌─────────────────────────────────┐ │
│ │ ● Gemma 3n E2B (Active)    3.1GB│ │
│ │ ○ Gemma 3 1B              0.5GB │ │
│ │ ○ Gemma 3 270M            0.3GB │ │
│ │ ○ Phi-4 Mini [Download]   3.9GB │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ 📊 EMBEDDING MODEL                  │
│ ┌─────────────────────────────────┐ │
│ │ ● EmbeddingGemma 512 (Active)   │ │
│ │ ○ EmbeddingGemma 256            │ │
│ │ ○ Gecko 64 (Fastest)            │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ 💾 STORAGE                          │
│ Models: 3.5GB used                  │
│ [Clear All Downloaded Models]       │
└─────────────────────────────────────┘
```

---

### Startup Flow Update

#### [MODIFY] [startup_viewmodel.dart](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/lib/ui/views/startup/startup_viewmodel.dart)

```diff
 Future<void> runStartupLogic() async {
+  // 1. Detect device capabilities
+  final capabilities = await _deviceService.getCapabilities();
+  
+  // 2. Get recommended models for this device
+  final recommended = _recommendationService.getRecommendedModels(capabilities);
+  
+  // 3. Download recommended models if not present
+  await _modelService.downloadModel(recommended.inferenceModel.id);
+  await _modelService.downloadModel(recommended.embeddingModel.id);
   // ... rest of logic
 }
```

---

### Dependencies

#### [MODIFY] [pubspec.yaml](file:///media/limcheekin/My%20Passport/ws/rag.wtf/offline_sync/pubspec.yaml)

```diff
 dependencies:
+  device_info_plus: ^12.3.0
+  system_info_plus: ^0.0.6
```

---

## Verification Plan

### Automated Tests

1. **Run existing tests** to ensure no regressions:
   ```bash
   cd /media/limcheekin/My\ Passport/ws/rag.wtf/offline_sync
   flutter test
   ```

2. **New unit tests** to add:
   - `test/services/device_capability_service_test.dart` — Mock device info responses
   - `test/services/model_recommendation_service_test.dart` — Verify tier→model mapping

### Manual Verification

Since device capability detection requires actual hardware, manual testing is essential:

1. **Web Platform Test**:
   - Run `flutter run -d chrome`
   - Verify startup detects web platform and selects appropriate model
   - Navigate to Settings and verify model switching UI appears

2. **Android/Desktop Test**:
   - Run on physical device or emulator
   - Verify RAM/storage detection shows reasonable values
   - Switch between models in Settings and confirm download/activation

3. **Model Switching Test**:
   - Download a second inference model from Settings
   - Switch to it and verify chat still works
   - Restart app and verify selected model persists

> [!TIP]
> For initial testing, you can use the web platform where device detection returns defaults, then test on Android for full capability detection.
