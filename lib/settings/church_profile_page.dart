import 'dart:convert';

import 'package:church_service_timer/app/controller.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:church_service_timer/live/running_service_bar.dart';
import 'package:church_service_timer/settings/image_crop_page.dart';
import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/shared/church_banner.dart';
import 'package:flutter/material.dart';

/// Church profile: the logo shown at the top of every page, the church
/// name and the banner used on printouts and reports. Photos are cropped
/// in the app to the shape each one needs: square for the logo, 3:1 for
/// the banner. Nothing is kept until Save.
class ChurchProfilePage extends StatefulWidget {
  final AppController controller;
  const ChurchProfilePage({super.key, required this.controller});
  @override
  State<ChurchProfilePage> createState() => _ChurchProfilePageState();
}

class _ChurchProfilePageState extends State<ChurchProfilePage> {
  AppController get c => widget.controller;
  late final TextEditingController name = TextEditingController(
    text: c.state.churchName,
  )..addListener(() => setState(() {}));
  late String logo = c.state.churchLogo;
  late String banner = c.state.churchBanner;
  String? logoError, bannerError, error;
  String? picking;
  bool saving = false;

  bool get busy => saving || picking != null;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  /// Picks a photo, then crops it to the shape [kind] needs.
  Future<void> pick(String kind) async {
    setState(() {
      picking = kind;
      if (kind == 'logo') {
        logoError = null;
      } else {
        bannerError = null;
      }
    });
    try {
      final photo = await c.port.pickChurchPhoto();
      if (photo == null || !mounted) return;
      final bytes = base64Decode(photo);
      final cropped = kind == 'logo'
          ? await ImageCropPage.logo(context, bytes)
          : await ImageCropPage.banner(context, bytes);
      if (cropped == null || !mounted) return;
      if (kind == 'logo') {
        churchLogoValue(cropped);
        setState(() => logo = cropped);
      } else {
        await validateBannerPixels(cropped);
        if (mounted) setState(() => banner = cropped);
      }
    } catch (_) {
      if (!mounted) return;
      const problem =
          'Could not use this photo. Choose a JPEG, PNG or WebP up to 5 MB and 40 megapixels.';
      setState(() {
        if (kind == 'logo') {
          logoError = problem;
        } else {
          bannerError = problem;
        }
      });
    } finally {
      if (mounted) setState(() => picking = null);
    }
  }

  Future<void> save() async {
    String value;
    try {
      value = churchNameValue(name.text);
    } catch (e) {
      setState(() => error = '$e');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    final saved = await c.commit((draft, _) {
      draft.churchName = value;
      draft.churchLogo = logo;
      draft.churchBanner = banner;
    });
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() {
        saving = false;
        error = c.error ?? 'Could not save. Try again.';
      });
    }
  }

  Widget section(String title, String note, List<Widget> children) {
    final colors = appColors(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(note, style: TextStyle(color: colors.muted, fontSize: 13)),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }

  Widget problem(String? text) => text == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            text,
            style: TextStyle(color: appColors(context).warning),
          ),
        );

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final shownName = name.text.trim().isEmpty
        ? 'Church Service Timer'
        : name.text.trim();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Church profile'),
        bottom: c.liveSession.active
            ? RunningServiceBar.forContext(context, controller: c)
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // What the top of every page will look like.
                  Container(
                    key: const ValueKey('profile-header-preview'),
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      children: [
                        ChurchTimerMark(logo: logo),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            shownName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 18),
                    child: Text(
                      'Preview of the top of each page. Tap the logo there to come back here.',
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ),
                  section(
                    'Logo',
                    'Square, shown at the top left of every page. After choosing a photo you crop it to a square.',
                    [
                      Row(
                        children: [
                          ChurchTimerMark(size: 72, logo: logo),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  key: const ValueKey('choose-church-logo'),
                                  onPressed: busy ? null : () => pick('logo'),
                                  icon: const Icon(Icons.crop_square),
                                  label: Text(
                                    picking == 'logo'
                                        ? 'Opening photo…'
                                        : logo.isEmpty
                                        ? 'Choose logo'
                                        : 'Change logo',
                                  ),
                                ),
                                if (logo.isNotEmpty)
                                  TextButton(
                                    key: const ValueKey('remove-church-logo'),
                                    onPressed: busy
                                        ? null
                                        : () => setState(() => logo = ''),
                                    child: const Text('Use built-in mark'),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      problem(logoError),
                    ],
                  ),
                  section(
                    'Church name',
                    'Shown at the top of every page, on the opening screen and on new service reports. Services already loaded and older reports keep the name they had.',
                    [
                      TextField(
                        controller: name,
                        enabled: !busy,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Church name (optional)',
                          hintText: 'e.g. Grace Community Church',
                          errorText: error,
                        ),
                      ),
                    ],
                  ),
                  section(
                    'Banner',
                    'Three times as wide as it is tall, used on printed services and reports. After choosing a photo you crop it to that shape.',
                    [
                      Semantics(
                        button: true,
                        label: 'Choose church banner',
                        child: InkWell(
                          key: const ValueKey('choose-church-banner'),
                          borderRadius: BorderRadius.circular(18),
                          onTap: busy ? null : () => pick('banner'),
                          child: ChurchProfileBanner(image: banner),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: busy ? null : () => pick('banner'),
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: Text(
                              picking == 'banner'
                                  ? 'Opening photo…'
                                  : banner.isEmpty
                                  ? 'Choose banner'
                                  : 'Change banner',
                            ),
                          ),
                          if (banner.isNotEmpty)
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(() => banner = ''),
                              child: const Text('Use built-in banner'),
                            ),
                        ],
                      ),
                      problem(bannerError),
                    ],
                  ),
                  FilledButton(
                    key: const ValueKey('save-church-profile'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: busy ? null : save,
                    child: Text(saving ? 'Saving…' : 'Save church profile'),
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
