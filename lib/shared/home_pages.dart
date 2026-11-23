import 'package:flutter/material.dart';

/// The Lyrics page's number. Live, Programs, Reports and Settings keep 0
/// to 3, as every key, test and saved place names them; Lyrics is shown
/// third, after Programs, by [homePageOrder].
const lyricsPage = 4;

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
  HomePage(2, 'Reports', Icons.assessment_outlined),
  HomePage(3, 'Settings', Icons.settings_outlined),
];

/// Where [page] sits in the navigation.
int homePageSlot(int page) => homePageOrder
    .indexWhere((p) => p.page == page)
    .clamp(0, homePageOrder.length - 1);

/// The page [slot] places along from the first, or null past either end.
int? homePageAt(int slot) =>
    slot < 0 || slot >= homePageOrder.length ? null : homePageOrder[slot].page;
