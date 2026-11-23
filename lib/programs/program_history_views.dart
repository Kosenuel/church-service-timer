import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/shared/finish_widgets.dart';
import 'package:church_service_timer/main.dart';
import 'package:church_service_timer/shared/app_menu.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/wide_layout.dart';
import 'package:flutter/material.dart';

extension ProgramHistoryViews on HomeState {
  /// Lists the earlier versions of [program], newest first, each with what
  /// changed in the version after it, and offers to restore one.
  Future<void> openVersionHistory(Timeline program) => pushAppPage<void>(
    context,
    builder: (pageContext) => AnimatedBuilder(
      animation: c,
      builder: (pageContext, _) {
        final current = c.state.programById(program.id);
        final versions = c.state.versionsOf(program.id);
        final colors = appColors(pageContext);
        return Scaffold(
          appBar: AppBar(
            flexibleSpace: finishBar(context),
            title: const Text('Version history'),
          ),
          body: current == null
              ? const Center(child: Text('This program was removed.'))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      current.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The last $programHistoryLimit saved versions are kept, and included in backups. Restoring keeps the current version here too.',
                      style: TextStyle(color: colors.muted),
                    ),
                    const SizedBox(height: 16),
                    if (versions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No earlier versions yet. Each time you save a change to this program, the version before it is kept here.',
                        ),
                      )
                    else
                      // In a card like the other lists, not bare rows.
                      FinishCard(
                        radius: 18,
                        flat: (child) => Material(
                          color: colors.surface,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: colors.border),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: child,
                        ),
                        child: AppMenuList(
                          key: const ValueKey('program-versions'),
                          children: [
                            for (var i = 0; i < versions.length; i++)
                              ListTile(
                                key: ValueKey('program-version-$i'),
                                leading: const Icon(Icons.history),
                                title: Text(
                                  'Until ${serviceDateLabel(versions[i].replacedWall)} · ${wallTime(versions[i].replacedWall)}',
                                ),
                                subtitle: Text(
                                  '${templateSummary(versions[i].program)}\nNext save: ${describeProgramChange(versions[i].program, i == 0 ? current : versions[i - 1].program)}',
                                ),
                                isThreeLine: true,
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () =>
                                    previewVersion(pageContext, current, i),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        );
      },
    ),
  );

  Future<void> previewVersion(
    BuildContext pageContext,
    Timeline current,
    int index,
  ) async {
    final version = c.state.versionsOf(current.id)[index];
    final restore = await showDialog<bool>(
      context: pageContext,
      animationStyle: reduceAppMotion(pageContext)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        // A short title; the date goes on the first line below.
        title: const Text('Earlier version'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Until ${serviceDateLabel(version.replacedWall)} · ${wallTime(version.replacedWall)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  templateSummary(version.program),
                  style: TextStyle(color: appColors(ctx).muted),
                ),
                const SizedBox(height: 8),
                for (final s in version.program.segments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('${s.durationText} · ${s.name}'),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Restoring replaces the current rundown and settings. The name stays “${current.name}”, and the current version is kept in history.',
                  style: TextStyle(color: appColors(ctx).muted),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('restore-version'),
            onPressed: c.busy || c.corrupt
                ? null
                : () => Navigator.pop(ctx, true),
            child: const Text('Restore this version'),
          ),
        ],
      ),
    );
    if (restore != true || !mounted) return;
    final ok = await c.commit(
      (draft, at) => draft.restoreVersion(current.id, index, at.wall),
    );
    if (!mounted) return;
    if (!ok) {
      await showError(c.error ?? 'The version could not be restored.');
      return;
    }
    if (pageContext.mounted) Navigator.of(pageContext).pop();
    // The replaced version is now first in history; restoring it undoes.
    offerUndo(
      'Version restored',
      () =>
          c.commit((draft, at) => draft.restoreVersion(current.id, 0, at.wall)),
    );
  }
}
