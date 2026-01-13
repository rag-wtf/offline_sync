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
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Initializing AI Models...',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (viewModel.hasError)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: ${viewModel.modelError ?? "Unknown error"}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              )
            else
              const CircularProgressIndicator(),
            const SizedBox(height: 16),
            if (viewModel.statusMessage != null) Text(viewModel.statusMessage!),
            if (viewModel.hasError)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: viewModel.retry,
                    child: const Text('Retry'),
                  ),
                  if (viewModel.needsToken) ...[
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: viewModel.enterToken,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Enter Token'),
                    ),
                  ],
                ],
              ),
          ],
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
