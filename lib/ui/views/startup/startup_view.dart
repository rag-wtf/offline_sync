import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:offline_sync/l10n/gen/app_localizations.dart';
import 'package:offline_sync/services/device_capability_service.dart';
import 'package:offline_sync/services/logging_service.dart';
import 'package:offline_sync/ui/utils/download_policy_localizations.dart';
import 'package:offline_sync/ui/utils/repo_link_copy.dart';
import 'package:offline_sync/ui/views/startup/startup_viewmodel.dart';
import 'package:stacked/stacked.dart';

class StartupView extends StackedView<StartupViewModel> {
  const StartupView({this.viewModel, this.onViewModelReadyCallback, super.key});

  final StartupViewModel? viewModel;
  final void Function(StartupViewModel viewModel)? onViewModelReadyCallback;

  @override
  Widget builder(
    BuildContext context,
    StartupViewModel viewModel,
    Widget? child,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withValues(alpha: 0.1),
              colorScheme.surface,
              colorScheme.tertiary.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated Logo/Icon
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: value,
                        child: Opacity(
                          opacity: value,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  colorScheme.primary,
                                  colorScheme.secondary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: colorScheme.primary.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.auto_awesome,
                              size: 48,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 32),

                  // App Title
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      children: [
                        Text(
                          l10n.startupTitle,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.startupSubtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Loading / Error State
                  if (viewModel.hasError)
                    _buildErrorState(context, viewModel)
                  else
                    _buildLoadingState(context, viewModel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context, StartupViewModel viewModel) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    return Column(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          l10n.initializingModels,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (viewModel.statusMessage != null) ...[
          // coverage:ignore-start
          const SizedBox(height: 8),
          Text(
            viewModel.localizedStatusMessage(AppLocalizations.of(context)) ??
                viewModel.statusMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          // coverage:ignore-end
        ],
        // Show device info
        if (viewModel.capabilities != null) ...[
          // coverage:ignore-start
          const SizedBox(height: 24),
          _buildDeviceInfo(context, viewModel.capabilities!),
          // coverage:ignore-end
        ],
      ],
    );
  }

  Widget _buildErrorState(BuildContext context, StartupViewModel viewModel) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);
    final policyReason = viewModel.downloadPolicyReason;
    final errorMessage = policyReason == null
        ? LoggingService.redact(
            viewModel.modelError?.toString() ?? l10n.unknownError,
          )
        : localizeDownloadPolicyReason(
            AppLocalizations.of(context),
            policyReason,
          );

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
              if (viewModel.statusMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  viewModel.localizedStatusMessage(
                        AppLocalizations.of(context),
                      ) ??
                      viewModel.statusMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer.withValues(alpha: 0.7),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: viewModel.retry,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.retryAction),
                  ),
                  if (viewModel.needsToken) ...[
                    // coverage:ignore-start
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: viewModel.enterToken,
                      child: Text(l10n.enterTokenAction),
                    ),
                    if (viewModel.erroredModelRepoPage != null) ...[
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        key: const Key('copyRepoLinkButton'),
                        onPressed: () => copyRepoLinkToClipboard(
                          context,
                          viewModel.erroredModelRepoPage!,
                        ),
                        icon: const Icon(Icons.copy, size: 16),
                        label: Text(l10n.copyRepoLinkAction),
                      ),
                    ],
                    // coverage:ignore-end
                  ],
                ],
              ),
            ],
          ),
        ),
        // Show device info
        if (viewModel.capabilities != null) ...[
          const SizedBox(height: 16),
          _buildDeviceInfo(context, viewModel.capabilities!),
        ],
      ],
    );
  }

  Widget _buildDeviceInfo(
    BuildContext context,
    DeviceCapabilities capabilities,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context);

    String formatMemory(int mb) {
      if (mb >= 1024) {
        return '${(mb / 1024).toStringAsFixed(1)} GB';
      }
      return '$mb MB';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.deviceInformation,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _DeviceInfoRow(
            icon: Icons.memory,
            label: l10n.ramLabel,
            value: formatMemory(capabilities.totalRamMB),
          ),
          const SizedBox(height: 8),
          _DeviceInfoRow(
            icon: Icons.storage,
            label: l10n.storageLabel,
            value: formatMemory(capabilities.availableStorageMB),
          ),
          const SizedBox(height: 8),
          _DeviceInfoRow(
            icon: Icons.computer,
            label: l10n.platformLabel,
            value: capabilities.platform,
          ),
          const SizedBox(height: 8),
          _DeviceInfoRow(
            icon: Icons.developer_board,
            label: l10n.gpuLabel,
            value: capabilities.hasGpu
                ? l10n.availableLabel
                : l10n.notAvailableLabel,
          ),
        ],
      ),
    );
  }

  @override
  StartupViewModel viewModelBuilder(BuildContext context) =>
      viewModel ?? StartupViewModel();

  @override
  void onViewModelReady(StartupViewModel viewModel) {
    final callback = onViewModelReadyCallback;
    if (callback != null) {
      callback(viewModel);
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => viewModel.runStartupLogic(),
    );
  }
}

// Helper widget for device info rows
class _DeviceInfoRow extends StatelessWidget {
  const _DeviceInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
