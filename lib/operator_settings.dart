part of 'main.dart';

extension OperatorSettings on _HomeState {
  Widget deviceManagement() => DeviceManagementPanel(controller: c);

  Future<void> sendPreparedCue(TextLayout cue) async {
    if (!await c.act('cue', value: cue) && mounted) {
      await showError(c.error ?? 'The cue could not be sent.');
    } else if (mounted &&
        c.hardware.enabled &&
        (!c.hardware.connected || c.hardware.held)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cue applied to the service and paired screens · LED sign unavailable or held',
          ),
        ),
      );
    }
  }

  Future<void> editSavedCue({int? index}) async {
    final old = index == null ? null : c.state.stageCues[index];
    final revision = c.state.stageCues.map((e) => e.toJson()).toString();
    final result = await compose(
      old ?? const TextLayout(''),
      index == null ? 'Create stage cue' : 'Edit stage cue',
      'Save cue',
    );
    if (result == null) return;
    final ok = await c.commit((draft, _) {
      require(
        draft.stageCues.map((e) => e.toJson()).toString() == revision,
        'The cue list changed. Please open it again.',
      );
      validateLayout(result);
      if (index == null) {
        require(
          draft.stageCues.length < 100,
          'Keep at most 100 prepared cues.',
        );
        draft.stageCues.add(result);
      } else {
        draft.stageCues[index] = result;
      }
    });
    if (!ok && mounted) await showError(c.error ?? 'Could not save cue.');
  }

  Widget stageCueSettings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Shared across all services. Editing here never sends to the sign.',
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: c.busy ? null : () => editSavedCue(),
        icon: const Icon(Icons.add),
        label: const Text('New cue'),
      ),
      const SizedBox(height: 16),
      if (c.state.stageCues.isEmpty)
        const Text('No prepared cues. Create one to show it on Live.'),
      panel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (final e in c.state.stageCues.asMap().entries) ...[
              if (e.key > 0)
                const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                title: Text(e.value.text),
                subtitle: Text(
                  styleSummary(e.value).substring(e.value.text.length + 3),
                ),
                onTap: c.busy ? null : () => editSavedCue(index: e.key),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Cue actions',
                  enabled: !c.busy,
                  onSelected: (action) async {
                    if (action == 'edit') {
                      await editSavedCue(index: e.key);
                      return;
                    }
                    if (action == 'delete') {
                      if (await confirm(
                        'Delete stage cue?',
                        'Remove “${e.value.text}” from every service’s Live buttons? Output already on stage stays unchanged.',
                        'Delete cue',
                      ))
                        await deleteCueWithUndo(e.key, e.value);
                      return;
                    }
                    await c.commit((draft, _) {
                      require(
                        e.key < draft.stageCues.length &&
                            draft.stageCues[e.key].toJson().toString() ==
                                e.value.toJson().toString(),
                        'The cue list changed.',
                      );
                      final next = e.key + (action == 'up' ? -1 : 1);
                      require(
                        next >= 0 && next < draft.stageCues.length,
                        'Cannot move this cue further.',
                      );
                      final cue = draft.stageCues.removeAt(e.key);
                      draft.stageCues.insert(next, cue);
                    });
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    if (e.key > 0)
                      const PopupMenuItem(value: 'up', child: Text('Move up')),
                    if (e.key + 1 < c.state.stageCues.length)
                      const PopupMenuItem(
                        value: 'down',
                        child: Text('Move down'),
                      ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete cue'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ],
  );
}
