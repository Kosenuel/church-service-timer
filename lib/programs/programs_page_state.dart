/// What the Programs page shows: search, filter, selection and, on wide
/// screens, the program open beside the list. Kept while switching tabs.
class ProgramsPageState {
  String query = '', filter = 'all';
  bool selecting = false;

  /// Names of the programs ticked while selecting.
  final selected = <String>{};

  /// The program open in the detail pane on wide screens.
  String? open;

  /// Bumped to clear the search field from outside it.
  int searchReset = 0;
}
