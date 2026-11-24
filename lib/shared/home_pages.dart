import 'package:flutter/material.dart';

/// The Lyrics page's number. Live, Programs, Reports and Settings keep 0
/// to 3, as every key, test and saved place names them; Lyrics is shown
/// third, after Programs, by [homePageOrder].
const lyricsPage = 4;

/// The Screens page's number, after Lyrics. It is a destination only of a
/// rail or top tabs; a phone's bottom bar has room for five, so Screens
/// stays a button on Live there (see [homePagesFor]).
const screensPage = 5;

/// One destination of the home screen's navigation.
class HomePage {
  final int page;
  final String name;
  final IconData icon;
  const HomePage(this.page, this.name, this.icon);
}

/// The pages in the order the navigation shows them.
const homePageOrder = [
  HomePage(0, 'Live', Icons.radio_button_checked),
  HomePage(1, 'Programs', Icons.view_timeline_outlined),
  HomePage(lyricsPage, 'Slides', Icons.lyrics_outlined),
  HomePage(screensPage, 'Screens', Icons.dashboard_customize_outlined),
  HomePage(2, 'Reports', Icons.assessment_outlined),
  HomePage(3, 'Settings', Icons.settings_outlined),
];

/// The pages a navigation shows: all of them on a rail or top tabs, all
/// but Screens on a phone's bottom bar.
List<HomePage> homePagesFor({required bool withScreens}) => withScreens
    ? homePageOrder
    : [
        for (final p in homePageOrder)
          if (p.page != screensPage) p,
      ];

/// Where [page] sits in the navigation [order] shows.
int homePageSlot(int page, [List<HomePage> order = homePageOrder]) =>
    order.indexWhere((p) => p.page == page).clamp(0, order.length - 1);

/// The page [slot] places along from the first, or null past either end.
int? homePageAt(int slot, [List<HomePage> order = homePageOrder]) =>
    slot < 0 || slot >= order.length ? null : order[slot].page;
