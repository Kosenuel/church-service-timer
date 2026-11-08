import 'package:flutter/material.dart';

/// What the Reports page shows: search, filters, list or graph, selection
/// and, on wide screens, the report open beside the list. Kept while
/// switching tabs.
class ReportsPageState {
  String query = '', filter = 'all', view = 'list';
  DateTimeRange? dates;
  bool selecting = false;

  /// Ids of the reports ticked while selecting.
  final selected = <String>{};

  /// The report open in the detail pane on wide screens.
  String? open;

  /// The report tapped in the Reports graph, shown in a card below it.
  String? graph;
}
