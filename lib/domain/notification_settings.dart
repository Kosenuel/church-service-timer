import 'package:church_service_timer/domain/domain.dart';

int notificationTimeoutValue(dynamic value) {
  require(
    value is int && {0, 15, 30, 60}.contains(value),
    'Choose 15, 30, 60 seconds or Until dismissed.',
  );
  return value as int;
}
