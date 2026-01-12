import 'package:flutter/material.dart';
import 'package:offline_sync/services/model_management_service.dart';
import 'package:offline_sync/ui/views/settings/settings_viewmodel.dart';
import 'package:stacked/stacked.dart';

class SettingsView extends StackedView<SettingsViewModel> {
  const SettingsView({super.key});

  @override
  Widget builder(
    BuildContext context,
    SettingsViewModel viewModel,
    Widget? child,
  ) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'AI Model Management',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...viewModel.models.map(
            (model) => _ModelTile(
              model: model,
              onDownload: () => viewModel.downloadModel(model.id),
            ),
          ),
        ],
      ),
    );
  }

  @override
  SettingsViewModel viewModelBuilder(BuildContext context) =>
      SettingsViewModel();

  @override
  void onViewModelReady(SettingsViewModel viewModel) {
    viewModel.setup();
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({required this.model, required this.onDownload});
  final ModelInfo model;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(model.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${model.status.name.toUpperCase()}'),
            if (model.status == ModelStatus.downloading)
              LinearProgressIndicator(value: model.progress),
          ],
        ),
        trailing: model.status == ModelStatus.notDownloaded
            ? IconButton(
                icon: const Icon(Icons.download),
                onPressed: onDownload,
              )
            : model.status == ModelStatus.downloaded
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
      ),
    );
  }
}
