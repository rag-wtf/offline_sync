import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:offline_sync/ui/views/startup/startup_viewmodel.dart';
import 'package:stacked/stacked.dart';

class StartupView extends StackedView<StartupViewModel> {
  const StartupView({super.key});

  @override
  Widget builder(
    BuildContext context,
    StartupViewModel viewModel,
    Widget? child,
  ) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (viewModel.hasError) ...[
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'Initialization Failed',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  viewModel.modelError?.toString() ??
                      'An unknown error occurred.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.tonal(
                      onPressed: viewModel.retry,
                      child: const Text('Retry'),
                    ),
                    if (viewModel.needsToken) ...[
                      const SizedBox(width: 16),
                      FilledButton(
                        onPressed: viewModel.enterToken,
                        child: const Text('Enter Token'),
                      ),
                    ],
                  ],
                ),
              ] else ...[
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 24),
                Text(
                  'Initializing AI Models...',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (viewModel.statusMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    viewModel.statusMessage!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  StartupViewModel viewModelBuilder(BuildContext context) => StartupViewModel();

  @override
  void onViewModelReady(StartupViewModel viewModel) => SchedulerBinding.instance
      .addPostFrameCallback((_) => viewModel.runStartupLogic());
}
