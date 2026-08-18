import 'package:flutter/material.dart';
import '../services/ai_service.dart';

/// Pill button shown in the app bar: displays the active model and opens
/// the model picker sheet. Lets the user switch models without digging
/// into Settings.
class ModelPickerButton extends StatelessWidget {
  final AiService aiService;
  final VoidCallback onChanged;

  const ModelPickerButton({
    super.key,
    required this.aiService,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => ModelPickerSheet(aiService: aiService),
          );
          onChanged();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy_rounded,
                size: 14,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  aiService.model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 14,
                color: theme.colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with provider presets on top and the live model list
/// (fetched from the current endpoint) below.
class ModelPickerSheet extends StatefulWidget {
  final AiService aiService;

  const ModelPickerSheet({super.key, required this.aiService});

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  bool _loading = true;
  String? _error;
  List<String> _models = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!widget.aiService.isConfigured) {
      setState(() {
        _loading = false;
        _error =
            'No API key configured for this endpoint. Add it in Settings first.';
      });
      return;
    }
    final models = await widget.aiService.fetchAvailableModels(
      widget.aiService.baseUrl,
      widget.aiService.apiKey,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _models = models;
      if (models.isEmpty) {
        _error = 'Could not fetch the model list from this endpoint.';
      }
    });
  }

  Future<void> _select(String model) async {
    await widget.aiService.saveSettings(
      apiKey: widget.aiService.apiKey,
      baseUrl: widget.aiService.baseUrl,
      model: model,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _switchProvider(AiProviderPreset preset) async {
    await widget.aiService.saveSettings(
      apiKey: widget.aiService.apiKey,
      baseUrl: preset.baseUrl,
      model: preset.defaultModel,
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Models',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.aiService.providerName,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Reload model list',
                    onPressed: _load,
                  ),
                ],
              ),
            ),

            // Provider presets
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: AiService.providerPresets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final preset = AiService.providerPresets[index];
                  final selected = widget.aiService.providerName == preset.name;
                  return ChoiceChip(
                    label: Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : null,
                      ),
                    ),
                    selected: selected,
                    selectedColor: theme.colorScheme.primary,
                    tooltip: preset.note ?? preset.baseUrl,
                    onSelected: (_) => _switchProvider(preset),
                  );
                },
              ),
            ),
            const Divider(height: 24),

            // Model list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cloud_off_rounded,
                                    size: 36, color: Colors.orange),
                                const SizedBox(height: 12),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _load,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _models.length,
                          itemBuilder: (context, index) {
                            final model = _models[index];
                            final selected = model == widget.aiService.model;
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                selected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                size: 18,
                                color: selected
                                    ? theme.colorScheme.primary
                                    : theme.iconTheme.color,
                              ),
                              title: Text(
                                model,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                              onTap: () => _select(model),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
