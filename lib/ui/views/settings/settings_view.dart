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
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final semanticWeightPct = (viewModel.semanticWeightDisplay * 100)
        .toStringAsFixed(0);
    final maxDocumentSizeText =
        l10n?.settingsMaxDocumentSize(viewModel.maxDocumentSizeMB) ??
        'Documents larger than ${viewModel.maxDocumentSizeMB} MB are rejected.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
                      ? l10n?.modelStatusError ??
                            'Model status is unavailable. Please retry.'
                      : l10n?.settingsSaveError ??
                            'Some settings could not be saved.',
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
            ),
          // AI Model Management Section
          const _SectionHeader(
            icon: Icons.memory_rounded,
            title: 'AI Model Management',
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
                          'Active Inference Model',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...viewModel.downloadedInferenceModels.asMap().entries.map((
                    entry,
                  ) {
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
                          // RadioListTile.groupValue is deprecated
                          // in favor of RadioGroup
                          // ignore: deprecated_member_use
                          groupValue: viewModel.activeInferenceModel?.id,
                          // RadioListTile.onChanged is deprecated
                          // in favor of RadioGroup
                          // ignore: deprecated_member_use
                          onChanged: (value) {
                            if (value != null) {
                              unawaited(viewModel.switchInferenceModel(value));
                            }
                          },
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
                                  'ACTIVE',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                        if (!isLast) const Divider(height: 1, indent: 56),
                      ],
                    );
                  }),
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
                          'Active Embedding Model',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...viewModel.downloadedEmbeddingModels.asMap().entries.map((
                    entry,
                  ) {
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
                          // RadioListTile.groupValue is deprecated
                          // in favor of RadioGroup
                          // ignore: deprecated_member_use
                          groupValue: viewModel.activeEmbeddingModel?.id,
                          // RadioListTile.onChanged is deprecated
                          // in favor of RadioGroup
                          // ignore: deprecated_member_use
                          onChanged: (value) {
                            if (value != null) {
                              unawaited(viewModel.switchEmbeddingModel(value));
                            }
                          },
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
                                  'ACTIVE',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : null,
                        ),
                        if (!isLast) const Divider(height: 1, indent: 56),
                      ],
                    );
                  }),
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
                        'Available Models',
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
                        onDelete: entry.value.status == ModelStatus.downloaded
                            ? () => viewModel.deleteModel(entry.value)
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
          const _SectionHeader(
            icon: Icons.tune_rounded,
            title: 'RAG Quality Settings',
            subtitle: 'Improve retrieval accuracy and response quality',
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Query Expansion'),
                  subtitle: const Text(
                    'Generate query variants for better recall',
                  ),
                  value: viewModel.queryExpansionEnabled,
                  onChanged: viewModel.toggleQueryExpansion,
                ),
                const Divider(height: 1, indent: 16),
                SwitchListTile(
                  title: const Text('LLM Reranking'),
                  subtitle: const Text(
                    'Use AI to reorder results by relevance',
                  ),
                  value: viewModel.rerankingEnabled,
                  onChanged: viewModel.toggleReranking,
                ),
                const Divider(height: 1, indent: 16),
                SwitchListTile(
                  title: const Text('Contextual Retrieval'),
                  subtitle: const Text(
                    'Add context to chunks for better retrieval',
                  ),
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
                    title: 'Chunk Overlap',
                    value:
                        '${viewModel.chunkOverlapDisplay.toStringAsFixed(0)}%',
                    subtitle: 'Context continuity between text chunks',
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
                    title: 'Semantic vs Keyword',
                    value: '$semanticWeightPct%',
                    subtitle: 'Balance between search methods',
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
          const _SectionHeader(
            icon: Icons.data_usage_rounded,
            title: 'Token Management',
            subtitle: 'Control context and history to fit model limits',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SliderSetting(
                    title: 'Search Top K',
                    value: '${viewModel.searchTopKDisplay.round()}',
                    subtitle: 'Context chunks retrieved from vector search',
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
                    title: 'Max History Messages',
                    value: '${viewModel.maxHistoryMessagesDisplay.round()}',
                    subtitle: 'Conversation history included in context',
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
                    title: 'Max Tokens',
                    value: viewModel.isMaxTokensCustomDisplay
                        ? '${viewModel.maxTokensDisplay.round()} (Custom)'
                        : '${viewModel.maxTokensDisplay.round()}',
                    subtitle: viewModel.isMaxTokensCustomDisplay
                        ? 'Default: ${viewModel.modelDefaultMaxTokens}'
                        : 'Maximum context window (input + output)',
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
          const _SectionHeader(
            icon: Icons.library_books_rounded,
            title: 'Knowledge Base',
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
              title: const Text('Manage Knowledge Base'),
              subtitle: Text(
                'Add, view, and delete documents\n$maxDocumentSizeText',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: viewModel.navigateToDocumentLibrary,
            ),
          ),

          const SizedBox(height: 32),

          // Device Information Section
          if (viewModel.capabilities != null) ...[
            const _SectionHeader(
              icon: Icons.devices_rounded,
              title: 'Device Information',
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
                    l10n?.huggingFaceTokenTitle ?? 'Hugging Face token',
                  ),
                  subtitle: Text(
                    viewModel.hasToken == true
                        ? l10n?.tokenStatusSaved ?? 'Token saved'
                        : l10n?.tokenStatusNotSet ?? 'No token saved',
                  ),
                  trailing: TextButton(
                    onPressed: viewModel.enterToken,
                    child: Text(
                      l10n?.enterOrReplaceToken ?? 'Enter or replace',
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(l10n?.clearSavedToken ?? 'Clear saved token'),
                  enabled: viewModel.hasToken == true,
                  onTap: viewModel.clearToken,
                ),
              ],
            ),
          ),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(l10n?.crashLogsTitle ?? 'Crash Logs'),
              subtitle: Text(
                l10n?.diagnosticsCount(viewModel.crashLogs.length) ??
                    '${viewModel.crashLogs.length} diagnostics',
              ),
              children: [
                if (viewModel.crashLogs.isEmpty)
                  ListTile(
                    title: Text(l10n?.noCrashLogs ?? 'No crash logs recorded'),
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
                      child: Text(l10n?.copyDiagnostics ?? 'Copy diagnostics'),
                    ),
                    TextButton(
                      onPressed: viewModel.crashLogs.isEmpty
                          ? null
                          : viewModel.clearCrashLogs,
                      child: Text(l10n?.clearCrashLogs ?? 'Clear Crash Logs'),
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
                l10n?.privateLocalStorageTitle ?? 'Private local storage',
              ),
              subtitle: Text(
                l10n?.privateLocalStorageSubtitle ??
                    'Local documents and models are excluded '
                        'from cloud backups.',
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(l10n?.clearChatHistoryTitle ?? 'Clear chat history'),
              subtitle: Text(
                l10n?.clearChatHistorySubtitle ??
                    'Delete locally saved conversations.',
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
          : model.status == ModelStatus.notDownloaded ||
                model.status == ModelStatus.error
          ? IconButton.filledTonal(
              icon: Icon(
                model.status == ModelStatus.error
                    ? Icons.refresh_rounded
                    : Icons.download_rounded,
              ),
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
          label: 'RAM',
          value: formatMemory(capabilities.totalRamMB),
          colorScheme: colorScheme,
          theme: theme,
        ),
        const SizedBox(height: 12),
        _DeviceInfoRow(
          icon: Icons.storage,
          label: 'Storage',
          value: formatMemory(capabilities.availableStorageMB),
          colorScheme: colorScheme,
          theme: theme,
        ),
        const SizedBox(height: 12),
        _DeviceInfoRow(
          icon: Icons.computer,
          label: 'Platform',
          value: capabilities.platform.toUpperCase(),
          colorScheme: colorScheme,
          theme: theme,
        ),
        const SizedBox(height: 12),
        _DeviceInfoRow(
          icon: Icons.developer_board,
          label: 'GPU',
          value: capabilities.hasGpu ? 'Available' : 'Not Available',
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
