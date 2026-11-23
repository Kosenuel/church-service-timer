import 'dart:async';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/screens/led_preview.dart';
import 'package:church_service_timer/screens/show_miniature.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/device_words.dart';
import 'package:church_service_timer/shared/home_widgets.dart';
import 'package:church_service_timer/shared/ui_tools.dart';
import 'package:church_service_timer/windows/second_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Opens the Screens panel as a page of its own: on a phone the whole
/// screen, on a computer the window.
Future<void> openScreensPanel(BuildContext context, AppController c) =>
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => ScreensPage(controller: c)));

/// This device's own screen as the panel names it.
String thisScreenName(AppController c) =>
    c.port.isDesktop ? 'This computer' : deviceText('This phone');

/// What this device's own screen is, under its name.
String thisScreenDetail(AppController c) {
  final second = c.secondScreen;
  final showing = second?.showingOn;
  return [
    if (second != null)
      'Second screen, full screen and the stage simulator'
    else
      'Full screen and the stage simulator',
    if (showing != null) 'Showing on ${stageMonitorLabel(showing)}',
  ].join(' · ');
}

/// The name of [s] in lists and chips.
String screenName(AppController c, StageScreenInfo s) => switch (s.kind) {
  'this' => thisScreenName(c),
  'web' => 'Web screen · ${s.name}',
  _ => s.name,
};

/// The Screens panel: scenes at the top (one tap sets every group), a
/// board of groups (one tap sets what a whole group shows), and the list
/// of screens with the group each is in. Nothing asks for confirmation
/// while changing what a group shows, moving a screen or applying a
/// scene, so it is quick to use mid-service.
class ScreensPage extends StatefulWidget {
  final AppController controller;
  const ScreensPage({super.key, required this.controller});

  @override
  State<ScreensPage> createState() => ScreensPageState();
}

class ScreensPageState extends State<ScreensPage> {
  AppController get c => widget.controller;
  ScreensController get screens => c.screens;

  /// What the last change did, read out and shown under the board.
  String status = '';

  /// Live's Lock controls, or another device in control, stop every change.
  bool get locked => c.uiLocked || !c.pairing.localControl || c.corrupt;

  void say(String text) {
    setState(() => status = text);
  }

  Future<void> run(Future<bool> Function() change, String done) async {
    final ok = await change();
    if (!mounted) return;
    say(ok ? done : (c.error ?? 'That was not saved. Try again.'));
  }

  String showName(String show) => screenShows[show] ?? show;

  int screensIn(String group) => screens.membersOf(group).length;

  String count(int n) => n == 1 ? '1 screen' : '$n screens';

  // ---- Asking for a name -------------------------------------------------

  Future<String?> askName(String title, String action, String initial) {
    final field = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      animationStyle: reduceAppMotion(context)
          ? AnimationStyle.noAnimation
          : null,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          key: const ValueKey('screens-name-field'),
          controller: field,
          autofocus: true,
          maxLength: screenNameLimit,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('screens-name-save'),
            onPressed: () => Navigator.pop(ctx, field.text),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  Future<bool> confirmDelete(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('screens-delete-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: appColors(ctx).error,
                foregroundColor: readable(appColors(ctx).error),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ==
      true;

  String freeName(String stem, Iterable<String> taken) {
    final lower = {for (final t in taken) t.toLowerCase()};
    for (var n = 1; ; n++) {
      final name = '$stem $n';
      if (!lower.contains(name.toLowerCase())) return name;
    }
  }

  // ---- Scenes ------------------------------------------------------------

  Future<void> saveScene() async {
    final name = await askName(
      'Save as a scene',
      'Save scene',
      freeName('Scene', screens.setup.scenes.map((s) => s.name)),
    );
    if (name == null || !mounted) return;
    final id = await screens.saveScene(name);
    if (!mounted) return;
    say(
      id == null
          ? (c.error ?? 'The scene was not saved.')
          : 'Saved “${name.trim()}”. One tap sets every group to it.',
    );
  }

  Future<void> sceneAction(ScreenScene scene, String action) async {
    switch (action) {
      case 'rename':
        final name = await askName('Rename scene', 'Rename', scene.name);
        if (name == null) return;
        await run(
          () => screens.renameScene(scene.id, name),
          'Renamed to “${name.trim()}”.',
        );
      case 'update':
        await run(
          () => screens.updateScene(scene.id),
          '“${scene.name}” now remembers what every group shows.',
        );
      case 'delete':
        if (!await confirmDelete(
          'Delete “${scene.name}”?',
          'Segments that name it will change nothing when they start.',
        )) {
          return;
        }
        await run(
          () => screens.deleteScene(scene.id),
          'Deleted “${scene.name}”.',
        );
    }
  }

  String sceneSummary(ScreenScene scene) => [
    for (final g in screens.setup.groups)
      if (scene.shows[g.id] case final show?) '${g.name}: ${showName(show)}',
  ].join(' · ');

  Widget scenesCard(bool narrow) {
    final colors = appColors(context);
    final setup = screens.setup;
    final showing = screens.showingScene;
    final buttons = <Widget>[
      for (final scene in setup.scenes)
        _SceneButton(
          key: ValueKey('scene-${scene.id}'),
          name: scene.name,
          summary: sceneSummary(scene),
          selected: showing?.id == scene.id,
          width: narrow ? 220 : null,
          onTap: locked
              ? null
              : () => run(
                  () => screens.applyScene(scene.id),
                  'Scene “${scene.name}” is on every group.',
                ),
          menu: locked ? null : (action) => sceneAction(scene, action),
        ),
      OutlinedButton.icon(
        key: const ValueKey('save-scene'),
        onPressed: locked ? null : saveScene,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Save as a scene'),
      ),
    ];
    return AppPanel(
      key: const ValueKey('screens-scenes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SCENES · ONE TAP SETS EVERY GROUP',
            style: sectionLabelStyle(context),
          ),
          const SizedBox(height: 10),
          if (narrow)
            SingleChildScrollView(
              key: const ValueKey('screens-scenes-row'),
              scrollDirection: Axis.horizontal,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, b) in buttons.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      b,
                    ],
                  ],
                ),
              ),
            )
          else
            Wrap(spacing: 8, runSpacing: 8, children: buttons),
          const SizedBox(height: 8),
          Text(
            setup.scenes.isEmpty
                ? 'A scene remembers what each group shows. Set the groups the way you want, then save that as a scene. A program segment can name a scene, so it switches by itself when that segment starts.'
                : 'A scene remembers what each group shows. A program segment can name a scene, so it switches by itself when that segment starts.',
            style: TextStyle(color: colors.muted, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  // ---- Groups ------------------------------------------------------------

  Future<void> addGroup() async {
    final name = await askName(
      'New group',
      'Add group',
      freeName('Group', screens.setup.groups.map((g) => g.name)),
    );
    if (name == null || !mounted) return;
    final id = await screens.addGroup(name);
    if (!mounted) return;
    say(
      id == null
          ? (c.error ?? 'The group was not added.')
          : 'Added “${name.trim()}”. Move screens into it below.',
    );
  }

  Future<void> groupAction(ScreenGroup group, String action) async {
    switch (action) {
      case 'rename':
        final name = await askName('Rename group', 'Rename', group.name);
        if (name == null) return;
        await run(
          () => screens.renameGroup(group.id, name),
          'Renamed to “${name.trim()}”.',
        );
      case 'default':
        await run(
          () => screens.setDefault(group.id),
          'Screens that connect for the first time join ${group.name}.',
        );
      case 'link':
        await showWebLink(group);
      case 'delete':
        final to = screens.setup.defaultGroup == group.id
            ? screens.setup.groups.firstWhere((g) => g.id != group.id)
            : screens.setup.defaultOne;
        if (!await confirmDelete(
          'Delete “${group.name}”?',
          'Its screens move to ${to.name}. Scenes forget it.',
        )) {
          return;
        }
        await run(
          () => screens.deleteGroup(group.id),
          'Deleted “${group.name}”. Its screens are in ${to.name}.',
        );
    }
  }

  /// The address that puts a browser in [group], for a screen to open.
  Future<void> showWebLink(ScreenGroup group) async {
    final base = c.webStageLocalUrl ?? c.webStageUrl;
    final link = base == null ? null : '$base/?group=${group.id}';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Web link for ${group.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              link == null
                  ? 'Start sharing to screens first (Settings › Screens & devices). The link then opens the stage display in this group.'
                  : 'A browser that opens this link joins ${group.name}, and stays in it when it joins again.',
            ),
            if (link != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                link,
                key: const ValueKey('screens-web-link'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        actions: [
          if (link != null)
            TextButton(
              onPressed: () {
                unawaited(Clipboard.setData(ClipboardData(text: link)));
                Navigator.pop(ctx);
                say('Copied the link for ${group.name}.');
              },
              child: const Text('Copy'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget groupCard(ScreenGroup group) {
    final colors = appColors(context);
    final setup = screens.setup;
    final members = screens.membersOf(group.id);
    final on = members.where((s) => s.connected).length;
    final isDefault = setup.defaultGroup == group.id;
    final slideUp = c.lyrics.showing && !c.lyrics.black;
    return AppPanel(
      key: ValueKey('group-${group.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      [
                        '$on of ${members.length} connected',
                        if (isDefault) 'default for new screens',
                      ].join(' · '),
                      key: ValueKey('group-${group.id}-count'),
                      style: TextStyle(color: colors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: ValueKey('group-${group.id}-menu'),
                tooltip: 'Group actions',
                enabled: !locked,
                onSelected: (a) => groupAction(group, a),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  if (!isDefault)
                    const PopupMenuItem(
                      value: 'default',
                      child: Text('Make default for new screens'),
                    ),
                  const PopupMenuItem(
                    value: 'link',
                    child: Text('Web link for this group'),
                  ),
                  if (setup.groups.length > 1)
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ShowMiniature(
            key: ValueKey('group-${group.id}-picture'),
            show: group.show,
            slide: slideUp,
            fallback: group.layout,
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Showing: '),
                TextSpan(
                  text: showName(group.show),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (showsSlides(group.show) && !slideUp)
                  TextSpan(
                    text:
                        ' · no slide up, so ${showName(group.layout).toLowerCase()}',
                    style: TextStyle(color: colors.muted),
                  ),
              ],
            ),
            key: ValueKey('group-${group.id}-showing'),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, box) {
              final columns = box.maxWidth >= 300 ? 3 : 2;
              final shows = screenShows.keys.toList();
              return Column(
                children: [
                  for (var i = 0; i < shows.length; i += columns) ...[
                    if (i > 0) const SizedBox(height: 6),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var j = i; j < i + columns; j++) ...[
                            if (j > i) const SizedBox(width: 6),
                            Expanded(
                              child: j < shows.length
                                  ? _ShowTile(
                                      key: ValueKey(
                                        'group-${group.id}-show-${shows[j]}',
                                      ),
                                      show: shows[j],
                                      label: showName(shows[j]),
                                      selected: group.show == shows[j],
                                      onTap: locked
                                          ? null
                                          : () => run(
                                              () => screens.setShow(
                                                group.id,
                                                shows[j],
                                              ),
                                              '${group.name} now shows ${showName(shows[j])} on ${count(screensIn(group.id))}.',
                                            ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          // Who looks at these screens: the person speaking sees cues,
          // the congregation does not. Scenes leave it alone.
          SwitchListTile(
            key: ValueKey('group-${group.id}-cues'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: group.cues,
            onChanged: locked
                ? null
                : (on) => run(
                    () => screens.setCues(group.id, on),
                    on
                        ? '${group.name} now shows cues and messages for the speaker.'
                        : '${group.name} no longer shows cues or messages.',
                  ),
            title: const Text('Shows cues'),
            subtitle: Text(
              group.cues
                  ? 'Stage cues, warnings and messages appear here'
                  : 'Cues and messages never appear here',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in members)
                _ScreenChip(name: screenName(c, s), on: s.connected),
              if (members.isEmpty)
                const _ScreenChip(name: 'No screens yet', on: false),
            ],
          ),
        ],
      ),
    );
  }

  /// The LED sign beside the groups: it is not in a group, as it shows
  /// the countdown and cues and never slides.
  Widget ledCard() {
    final colors = appColors(context);
    return AppPanel(
      key: const ValueKey('led-sign-card'),
      padding: const EdgeInsets.all(16),
      child: ListenableBuilder(
        listenable: c.hardware,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              c.hardware.rememberedName.isEmpty
                  ? 'LED sign'
                  : c.hardware.rememberedName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              ledSignState(c),
              key: const ValueKey('led-sign-card-state'),
              style: TextStyle(
                color: ledSignLive(c) ? colors.muted : colors.warning,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            LedSignMatrix(controller: c),
            const SizedBox(height: 10),
            const Text(
              'Shows the countdown and cues. Never slides.',
              key: ValueKey('led-sign-card-line'),
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              c.hardware.enabled
                  ? 'The picture is what this app last sent to the sign. The sign is not in a group.'
                  : 'The LED simulator: what a sign would show. A sign is not in a group.',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget newGroupButton() => OutlinedButton.icon(
    key: const ValueKey('new-group'),
    onPressed: locked || screens.setup.groups.length >= screenGroupLimit
        ? null
        : addGroup,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(96),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    icon: const Icon(Icons.add),
    label: const Text('New group'),
  );

  Widget board(double width) {
    const gap = 14.0, least = 300.0;
    final columns = ((width + gap) / (least + gap)).floor().clamp(1, 3);
    final groups = screens.setup.groups;
    final cells = [
      for (final g in groups) groupCard(g),
      if (hasLedSign(c)) ledCard(),
      newGroupButton(),
    ];
    if (columns == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, cell) in cells.indexed) ...[
            if (i > 0) const SizedBox(height: gap),
            cell,
          ],
        ],
      );
    }
    final cell = (width - gap * (columns - 1)) / columns;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [for (final w in cells) SizedBox(width: cell, child: w)],
    );
  }

  // ---- Screens -----------------------------------------------------------

  String screenDetail(StageScreenInfo s) {
    final state = s.connected ? 'connected' : 'not connected';
    return switch (s.kind) {
      'this' => thisScreenDetail(c),
      'web' => 'Browser · $state',
      _ => [
        'Paired stage screen · $state',
        if (s.olderApp) 'older app: shows the countdown for Slides and timer',
      ].join(' · '),
    };
  }

  Widget screensCard() {
    final colors = appColors(context);
    final setup = screens.setup;
    final list = screens.screens;
    return AppPanel(
      key: const ValueKey('screens-list'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'SCREENS · WHICH GROUP EACH IS IN',
            style: sectionLabelStyle(context),
          ),
          const SizedBox(height: 10),
          for (final s in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                key: ValueKey('screen-row-${s.key}'),
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: colors.input,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final name = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          screenName(c, s),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 5, right: 6),
                              child: _Dot(on: s.connected),
                            ),
                            Expanded(
                              child: Text(
                                screenDetail(s),
                                style: TextStyle(
                                  color: s.olderApp
                                      ? colors.warning
                                      : colors.muted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                    final current = screens.groupOf(s.key);
                    final chooser = _GroupChooser(
                      key: ValueKey('screen-group-${s.key}'),
                      label: 'Group for ${screenName(c, s)}',
                      value: current,
                      groups: setup.groups,
                      onChanged: locked
                          ? null
                          : (g) => unawaited(
                              run(
                                () => screens.move(s.key, g.id),
                                '${screenName(c, s)} moved to ${g.name} and now shows ${showName(g.show)}.',
                              ),
                            ),
                    );
                    if (box.maxWidth < 460) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          name,
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: chooser,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: name),
                        const SizedBox(width: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 160,
                            maxWidth: 240,
                          ),
                          child: chooser,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          // Where a browser goes when it opens the plain address.
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              key: const ValueKey('screen-row-new-web'),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New web screens',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Browsers that open the plain address, not a group’s link',
                        style: TextStyle(color: colors.muted, fontSize: 13),
                      ),
                    ],
                  ),
                  _GroupChooser(
                    key: const ValueKey('screen-group-new-web'),
                    label: 'Group for new web screens',
                    value: screens.webDefault,
                    groups: setup.groups,
                    onChanged: locked
                        ? null
                        : (g) => unawaited(
                            run(
                              () => screens.move(newWebScreensKey, g.id),
                              'Web screens that join now go to ${g.name}.',
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          Text(
            'A screen is in exactly one group. Move it by choosing another group here, even mid-service. A phone or tablet that pairs for the first time joins ${setup.defaultOne.name}, the default group. A browser joins the group of the link it opens (Web link for this group is on each group’s menu), or the group for new web screens.',
            style: TextStyle(color: colors.muted, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final colors = appColors(context);
      return PopScope(
        canPop: !c.uiLocked,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Screens'),
            actions: [
              if (locked)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Icon(Icons.lock, color: colors.muted),
                ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, space) {
                final narrow = space.maxWidth < 600;
                final pad = narrow ? 16.0 : 24.0;
                final width = (space.maxWidth - pad * 2).clamp(0.0, 1180.0);
                return FocusTraversalGroup(
                  child: SingleChildScrollView(
                    key: const ValueKey('screens-page'),
                    padding: EdgeInsets.fromLTRB(pad, 12, pad, 32),
                    child: Center(
                      child: SizedBox(
                        width: width,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'One tap sets what a whole group shows; a scene sets every group at once.',
                              style: TextStyle(color: colors.muted),
                            ),
                            if (locked) ...[
                              const SizedBox(height: 6),
                              Text(
                                c.uiLocked
                                    ? 'Controls are locked on Live.'
                                    : 'Take control on this device to change the screens.',
                                key: const ValueKey('screens-locked'),
                                style: TextStyle(color: colors.warning),
                              ),
                            ],
                            const SizedBox(height: 14),
                            scenesCard(narrow),
                            const SizedBox(height: 14),
                            board(width),
                            const SizedBox(height: 8),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                status,
                                key: const ValueKey('screens-status'),
                                style: TextStyle(color: colors.muted),
                              ),
                            ),
                            const SizedBox(height: 8),
                            screensCard(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    },
  );
}

/// A scene: its name and what it sets, lit while the groups show it, with
/// a menu to rename, update or delete it.
class _SceneButton extends StatelessWidget {
  final String name, summary;
  final bool selected;
  final double? width;
  final VoidCallback? onTap;
  final ValueChanged<String>? menu;
  const _SceneButton({
    super.key,
    required this.name,
    required this.summary,
    required this.selected,
    required this.onTap,
    required this.menu,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? colors.accent : colors.border,
        width: selected ? 2 : 1,
      ),
    );
    final body = Material(
      color: selected ? colors.accent.withValues(alpha: .12) : colors.input,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      summary,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Scene actions',
                enabled: menu != null,
                onSelected: menu,
                icon: const Icon(Icons.more_vert, size: 20),
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(
                    value: 'update',
                    child: Text('Update to what the groups show now'),
                  ),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: 'Scene $name',
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: 170, maxWidth: width ?? 340),
        child: SizedBox(width: width, child: body),
      ),
    );
  }
}

/// One of the six things a group can show: its picture and its name, lit
/// while chosen. One tap sets the whole group.
class _ShowTile extends StatelessWidget {
  final String show, label;
  final bool selected;
  final VoidCallback? onTap;
  const _ShowTile({
    super.key,
    required this.show,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(
        color: selected ? colors.accent : colors.border,
        width: selected ? 2 : 1,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null && !selected ? .55 : 1,
        child: Material(
          color: selected
              ? colors.accent.withValues(alpha: .12)
              : Colors.transparent,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Column(
                children: [
                  ShowMiniature(show: show, slide: true, small: true),
                  const SizedBox(height: 4),
                  // Flexible: the row's tiles share the tallest one's
                  // height, worked out to a fraction of a pixel.
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        color: selected ? colors.text : colors.muted,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The group a screen is in, as a button that lists the groups to move
/// it to.
class _GroupChooser extends StatelessWidget {
  final String label;
  final ScreenGroup value;
  final List<ScreenGroup> groups;
  final ValueChanged<ScreenGroup>? onChanged;
  const _GroupChooser({
    super.key,
    required this.label,
    required this.value,
    required this.groups,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return PopupMenuButton<String>(
      tooltip: label,
      enabled: onChanged != null,
      initialValue: value.id,
      onSelected: (id) {
        final g = groups.where((g) => g.id == id).firstOrNull;
        if (g != null && g.id != value.id) onChanged?.call(g);
      },
      itemBuilder: (ctx) => [
        for (final g in groups)
          PopupMenuItem(
            value: g.id,
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: g.id == value.id
                      ? Icon(Icons.check, size: 18, color: colors.accent)
                      : null,
                ),
                Flexible(child: Text(g.name)),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value.name,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: onChanged == null ? colors.muted : colors.text,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, color: colors.muted),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool on;
  const _Dot({required this.on});
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: on ? colors.success : colors.muted,
      ),
    );
  }
}

class _ScreenChip extends StatelessWidget {
  final String name;
  final bool on;
  const _ScreenChip({required this.name, required this.on});
  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.input,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(on: on),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12,
                color: on ? colors.text : colors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
