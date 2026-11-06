// Saves the benchmark summaries to build/perf/scroll_benchmarks.json, for
// scripts/perf_report.py.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data != null)
      await writeResponseData(
        data,
        testOutputFilename: 'scroll_benchmarks',
        destinationDirectory: 'build/perf',
      );
  },
);
