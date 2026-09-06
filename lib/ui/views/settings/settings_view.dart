import 'dart:async';

import 'package:flutter/material.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/ui/views/settings/settings_viewmodel.dart';
import 'package:stacked/stacked.dart';

class SettingsView extends StackedView<SettingsViewModel> {
  const SettingsView({
    this.viewModel,
    this.onViewModelReadyCallback,
    super.key,
  });

  final SettingsViewModel? viewModel;
  final void Function(SettingsViewModel viewModel)? onViewModelReadyCallback;

  @override
  Widget builder(
    BuildContext context,
    SettingsViewModel viewModel,
    Widget? child,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final semanticWeightPct = (viewModel.semanticWeightDisplay * 100)
        .toStringAsFixed(0);
    final maxDocumentSizeText = l10n.settingsMaxDocumentSize(
      viewModel.maxDocumentSizeMB,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        elevation: 0,
        scrolledUnderElevation: 4,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (viewModel.hasModelStatusError || viewModel.settingsError != null)
            Card(
              color: colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(Icons.error_outline, color: colorScheme.error),
                title: Text(
                  viewModel.settingsError == null
                      ? l10n.modelStatusError
                      : l10n.settingsSaveError,
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
            ),
          // AI Model Management Section
          _SectionHeader(
            icon: Icons.memory_rounded,
            title: l10n.modelsSection,
          ),
          const SizedBox(height: 12),

          // Active Inference Model Selection (show only if >1 downloaded)
          if (viewModel.downloadedInferenceModels.length > 1) ...[
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.psychology_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.activeInferenceModel,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  RadioGroup<String>(
                    groupValue: viewModel.activeInferenceModel?.id,
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(viewModel.switchInferenceModel(value));
                      }
                    },
                    child: Column(
                      children: viewModel.downloadedInferenceModels
                          .asMap()
                          .entries
                          .map((entry) {
                            final model = entry.value;
                            final isLast =
                                entry.key ==
                                viewModel.downloadedInferenceModels.length - 1;
                            final isActive =
                                viewModel.activeInferenceModel?.id == model.id;
                            return Column(
                              children: [
                                RadioListTile<String>(
                                  value: model.id,
                                  title: Text(
                                    model.name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: isActive
                                      ? Text(
                                          l10n.activeLabel,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        )
                                      : null,
                                ),
                                if (!isLast)
                                  const Divider(height: 1, indent: 56),
                              ],
                            );
                          })
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Active Embedding Model Selection (show only if >1 downloaded)
          if (viewModel.downloadedEmbeddingModels.length > 1) ...[
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.hub_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.activeEmbeddingModel,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  RadioGroup<String>(
                    groupValue: viewModel.activeEmbeddingModel?.id,
                    onChanged: (value) {
                      if (value != null) {
                        unawaited(viewModel.switchEmbeddingModel(value));
                      }
                    },
                    child: Column(
                      children: viewModel.downloadedEmbeddingModels
                          .asMap()
                          .entries
                          .map((entry) {
                            final model = entry.value;
                            final isLast =
                                entry.key ==
                                viewModel.downloadedEmbeddingModels.length - 1;
                            final isActive =
                                viewModel.activeEmbeddingModel?.id == model.id;
                            return Column(
                              children: [
                                RadioListTile<String>(
                                  value: model.id,
                                  title: Text(
                                    model.name,
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: isActive
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                    ),
                                  ),
                                  subtitle: isActive
                                      ? Text(
                                          l10n.activeLabel,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                        )
                                      : null,
                                ),
                                if (!isLast)
                                  const Divider(height: 1, indent: 56),
                              ],
                            );
                          })
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Available Models for Download
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_download_rounded,
                        size: 18,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.availableModels,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                ...viewModel.models.asMap().entries.map((entry) {
                  final isLast = entry.key == viewModel.models.length - 1;
                  return Column(
                    children: [
                      _ModelTile(
                        model: entry.value,
                        onDownload: () =>
                            viewModel.downloadModel(entry.value.id),
                        onDelete:
                            entry.value.status == ModelStatus.downloaded ||
                                entry.value.status == ModelStatus.error
                            ? () => viewModel.deleteModel(entry.value.id)
                            : null,
                      ),
                      if (!isLast) const Divider(height: 1, indent: 16),
                    ],
                  );
                }),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // RAG Quality Settings Section
          _SectionHeader(
            icon: Icons.tune_rounded,
            title: l10n.ragQualitySettings,
            subtitle: l10n.ragQualitySettingsSubtitle,
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(l10n.queryExpansionTitle),
                  subtitle: Text(l10n.queryExpansionSubtitle),
                  value: viewModel.queryExpansionEnabled,
                  onChanged: viewModel.toggleQueryExpansion,
                ),
                const Divider(height: 1, indent: 16),
                SwitchListTile(
                  title: Text(l10n.rerankingTitle),
                  subtitle: Text(l10n.rerankingSubtitle),
                  value: viewModel.rerankingEnabled,
                  onChanged: viewModel.toggleReranking,
                ),
                const Divider(height: 1, indent: 16),
                SwitchListTile(
                  title: Text(l10n.contextualRetrievalTitle),
                  subtitle: Text(l10n.contextualRetrievalSubtitle),
                  value: viewModel.contextualRetrievalEnabled,
                  onChanged: viewModel.toggleContextualRetrieval,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Slider settings Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SliderSetting(
                    title: l10n.chunkOverlapTitle,
                    value:
                        '${viewModel.chunkOverlapDisplay.toStringAsFixed(0)}%',
                    subtitle: l10n.chunkOverlapSubtitle,
                    slider: Slider(
                      value: viewModel.chunkOverlapDisplay,
                      max: 30,
                      divisions: 6,
                      label:
                          '${viewModel.chunkOverlapDisplay.toStringAsFixed(0)}'
                          '%',
                      onChanged: viewModel.onChunkOverlapChanged,
                      onChangeEnd: viewModel.onChunkOverlapChangeEnd,
                    ),
                  ),
                  const Divider(height: 24),
                  _SliderSetting(
                    title: l10n.semanticWeightTitle,
                    value: '$semanticWeightPct%',
                    subtitle: l10n.semanticWeightSubtitle,
                    slider: Slider(
                      value: viewModel.semanticWeightDisplay,
                      divisions: 10,
                      label: '$semanticWeightPct%',
                      onChanged: viewModel.onSemanticWeightChanged,
                      onChangeEnd: viewModel.onSemanticWeightChangeEnd,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Token Management Section
          _SectionHeader(
            icon: Icons.data_usage_rounded,
            title: l10n.tokenManagementTitle,
            subtitle: l10n.tokenManagementSubtitle,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SliderSetting(
                    title: l10n.searchTopKTitle,
                    value: '${viewModel.searchTopKDisplay.round()}',
                    subtitle: l10n.searchTopKSubtitle,
                    slider: Slider(
                      value: viewModel.searchTopKDisplay,
                      min: 1,
                      max: 5,
                      divisions: 4,
                      label: '${viewModel.searchTopKDisplay.round()}',
                      onChanged: viewModel.onSearchTopKChanged,
                      onChangeEnd: viewModel.onSearchTopKChangeEnd,
                    ),
                  ),
                  const Divider(height: 24),
                  _SliderSetting(
                    title: l10n.maxHistoryMessagesTitle,
                    value: '${viewModel.maxHistoryMessagesDisplay.round()}',
                    subtitle: l10n.maxHistoryMessagesSubtitle,
                    slider: Slider(
                      value: viewModel.maxHistoryMessagesDisplay,
                      max: 5,
                      divisions: 5,
                      label: '${viewModel.maxHistoryMessagesDisplay.round()}',
                      onChanged: viewModel.onMaxHistoryMessagesChanged,
                      onChangeEnd: viewModel.onMaxHistoryMessagesChangeEnd,
                    ),
                  ),
                  const Divider(height: 24),
                  _SliderSetting(
                    title: l10n.maxTokensTitle,
                    value: viewModel.isMaxTokensCustomDisplay
                        ? '${viewModel.maxTokensDisplay.round()} '
                              '${l10n.customLabel}'
                        : '${viewModel.maxTokensDisplay.round()}',
                    subtitle: viewModel.isMaxTokensCustomDisplay
                        ? l10n.defaultMaxTokens(viewModel.modelDefaultMaxTokens)
                        : l10n.maxTokensSubtitle,
                    slider: Slider(
                      value: viewModel.maxTokensDisplay,
                      min: 512,
                      max: viewModel.maxTokensLimit,
                      divisions: ((viewModel.maxTokensLimit - 512) / 256)
                          .round()
                          .clamp(1, 100),
                      label: '${viewModel.maxTokensDisplay.round()}',
                      onChanged: viewModel.onMaxTokensChanged,
                      onChangeEnd: viewModel.onMaxTokensChangeEnd,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Knowledge Base Section
          _SectionHeader(
            icon: Icons.library_books_rounded,
            title: l10n.knowledgeBaseTitle,
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.folder_open_rounded,
                  color: colorScheme.primary,
                ),
              ),
              title: Text(l10n.manageKnowledgeBase),
              subtitle: Text(
                '${l10n.knowledgeBaseSubtitle}\n$maxDocumentSizeText',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: viewModel.navigateToDocumentLibrary,
            ),
          ),

          const SizedBox(height: 32),

          // Device Information Section
          if (viewModel.capabilities != null) ...[
            _SectionHeader(
              icon: Icons.devices_rounded,
              title: l10n.deviceInformation,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _DeviceInfoSection(
                  capabilities: viewModel.capabilities!,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],

          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: Text(
                    l10n.huggingFaceTokenTitle,
                  ),
                  subtitle: Text(
                    viewModel.hasToken == true
                        ? l10n.tokenStatusSaved
                        : l10n.tokenStatusNotSet,
                  ),
                  trailing: TextButton(
                    onPressed: viewModel.enterToken,
                    child: Text(
                      l10n.enterOrReplaceToken,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(l10n.clearSavedToken),
                  enabled: viewModel.hasToken == true,
                  onTap: viewModel.clearToken,
                ),
              ],
            ),
          ),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(l10n.crashLogsTitle),
              subtitle: Text(
                l10n.diagnosticsCount(viewModel.crashLogs.length),
              ),
              children: [
                if (viewModel.crashLogs.isEmpty)
                  ListTile(
                    title: Text(l10n.noCrashLogs),
                  )
                else
                  SizedBox(
                    height: 180,
                    child: ListView.builder(
                      itemCount: viewModel.crashLogs.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(viewModel.crashLogs[index]),
                      ),
                    ),
                  ),
                OverflowBar(
                  children: [
                    TextButton(
                      onPressed: viewModel.crashLogs.isEmpty
                          ? null
                          : viewModel.exportCrashLogs,
                      child: Text(l10n.copyDiagnostics),
                    ),
                    TextButton(
                      onPressed: viewModel.crashLogs.isEmpty
                          ? null
                          : viewModel.clearCrashLogs,
                      child: Text(l10n.clearCrashLogs),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(
                l10n.privateLocalStorageTitle,
              ),
              subtitle: Text(
                l10n.privateLocalStorageSubtitle,
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(l10n.clearChatHistoryTitle),
              subtitle: Text(
                l10n.clearChatHistorySubtitle,
              ),
              onTap: viewModel.clearChatHistory,
            ),
          ),
        ],
      ),
    );
  }

  @override
  SettingsViewModel viewModelBuilder(BuildContext context) =>
      viewModel ?? SettingsViewModel();

  @override
  void onViewModelReady(SettingsViewModel viewModel) {
    final callback = onViewModelReadyCallback;
    if (callback != null) {
      callback(viewModel);
      return;
    }
    viewModel.setup();
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.slider,
  });

  final String title;
  final String value;
  final String subtitle;
  final Slider slider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        slider,
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.onDownload,
    this.onDelete,
  });
  final ModelInfo model;
  final VoidCallback onDownload;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color statusColor;
    IconData statusIcon;
    switch (model.status) {
      case ModelStatus.downloaded:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle_rounded;
      case ModelStatus.downloading:
        statusColor = colorScheme.primary;
        statusIcon = Icons.downloading_rounded;
      case ModelStatus.error:
        statusColor = colorScheme.error;
        statusIcon = Icons.error_rounded;
      case ModelStatus.notDownloaded:
        statusColor = colorScheme.outline;
        statusIcon = Icons.cloud_download_outlined;
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(statusIcon, color: statusColor),
      ),
      title: Text(
        model.name,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            model.status.name.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (model.status == ModelStatus.downloading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: model.progress,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          if (model.errorMessage != null)
            Text(
              model.errorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
        ],
      ),
      trailing: model.status == ModelStatus.downloaded
          ? IconButton.filledTonal(
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            )
          : model.status == ModelStatus.error
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: onDownload,
                ),
                IconButton.filledTonal(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ],
            )
          : model.status == ModelStatus.notDownloaded
          ? IconButton.filledTonal(
              icon: const Icon(Icons.download_rounded),
              onPressed: onDownload,
            )
          : null,
    );
  }
}

// Device Information Section Widget
class _DeviceInfoSection extends StatelessWidget {
  const _DeviceInfoSection({required this.capabilities});

  final DeviceCapabilities capabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    String formatMemory(int mb) {
      if (mb >= 1024) {
        return '${(mb / 1024).toStringAsFixed(1)} GB';
      }
      return '$mb MB';
    }

    return Column(
      children: [
        _DeviceInfoRow(
          icon: Icons.memory,
          label: l10n.ramLabel,
          value: formatMemory(capabilities.totalRamMB),
          colorScheme: colorScheme,
          theme: theme,
        ),
        const SizedBox(height: 12),
        _DeviceInfoRow(
          icon: Icons.storage,
          label: l10n.storageLabel,
          value: formatMemory(capabilities.availableStorageMB),
          colorScheme: colorScheme,
          theme: theme,
        ),
        const SizedBox(height: 12),
        _DeviceInfoRow(
          icon: Icons.computer,
          label: l10n.platformLabel,
          value: capabilities.platform.toUpperCase(),
          colorScheme: colorScheme,
          theme: theme,
        ),
        const SizedBox(height: 12),
        _DeviceInfoRow(
          icon: Icons.developer_board,
          label: l10n.gpuLabel,
          value: capabilities.hasGpu
              ? l10n.availableLabel
              : l10n.notAvailableLabel,
          colorScheme: colorScheme,
          theme: theme,
        ),
      ],
    );
  }
}

// Helper widget for device info rows in settings
class _DeviceInfoRow extends StatelessWidget {
  const _DeviceInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
    required this.theme,
  });

  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
