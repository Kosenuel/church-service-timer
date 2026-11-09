import 'package:church_service_timer/shared/app_theme.dart';
import 'package:church_service_timer/domain/domain.dart';
import 'package:flutter/material.dart';

/// How a finished service or segment compared with its plan, in one
/// vocabulary for every Reports screen: "On time" within a second,
/// otherwise "3m 0s over" or "2m 0s under". Live, while a service runs,
/// says "ahead" or "behind" instead, because that is still a projection.
String outcomeLabel(int varianceMs) => varianceMs.abs() < 1000
    ? 'On time'
    : '${durationLabel(varianceMs.abs())} ${varianceMs > 0 ? 'over' : 'under'}';

/// The colour for [outcomeLabel]: over is warm, under is cool and on time
/// is the accent, on every Reports screen.
Color outcomeColor(AppPalette colors, int varianceMs) => varianceMs.abs() < 1000
    ? colors.accent
    : varianceMs > 0
    ? colors.warning
    : colors.info;
