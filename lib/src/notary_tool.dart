import 'dart:convert';
import 'dart:io';

import 'package:dmg/src/utils.dart';

/// Credentials for Apple notarization
class NotaryCredentials {
  final String appleId;
  final String password;
  final String teamId;

  NotaryCredentials({
    required this.appleId,
    required this.password,
    required this.teamId,
  });
}

/// Prompt user for notarization credentials via stdin
NotaryCredentials promptNotaryCredentials() {
  stdout.write('Enter Apple ID: ');
  final appleId = stdin.readLineSync()?.trim() ?? '';

  stdout.write('Enter App-Specific Password: ');
  final password = stdin.readLineSync()?.trim() ?? '';

  stdout.write('Enter Team ID: ');
  final teamId = stdin.readLineSync()?.trim() ?? '';

  if (appleId.isEmpty || password.isEmpty || teamId.isEmpty) {
    throw Exception(
        'All notary credentials (Apple ID, Password, Team ID) are required.');
  }

  return NotaryCredentials(
    appleId: appleId,
    password: password,
    teamId: teamId,
  );
}

/// Submit DMG for notarization with error handling
String? runNotaryTool(
    String dmg, NotaryCredentials credentials, bool isVerbose) {
  try {
    if (!File(dmg).existsSync()) {
      log.warning('DMG file does not exist: $dmg');
      return null;
    }

    log.info('Submitting for notarization...');

    final result = Process.runSync('xcrun', [
      'notarytool',
      'submit',
      dmg,
      '--apple-id',
      credentials.appleId,
      '--password',
      credentials.password,
      '--team-id',
      credentials.teamId,
    ]);

    if (result.exitCode != 0) {
      log.warning(
          'Notarization submission failed with exit code ${result.exitCode}');
      log.warning('Error: ${result.stderr}');
      return null;
    }

    final output = result.stdout as String;

    if (isVerbose) {
      log.info(output);
    }

    return output;
  } catch (e) {
    log.warning('Exception during notarization submission: $e');
    return null;
  }
}

/// Waits for and checks notary state using `xcrun notarytool log` (JSON)
Future<bool> waitAndCheckNotaryState(
  String notaryId,
  NotaryCredentials credentials,
  File logFile,
  bool isVerbose,
) async {
  do {
    await Future.delayed(const Duration(seconds: 30));

    log.info('Checking for the notary result...');

    if (logFile.existsSync()) {
      logFile.deleteSync();
    }

    Process.runSync('xcrun', [
      'notarytool',
      'log',
      notaryId,
      '--apple-id',
      credentials.appleId,
      '--password',
      credentials.password,
      '--team-id',
      credentials.teamId,
      logFile.path,
    ]);

    if (!logFile.existsSync()) {
      log.info('Still in processing. Waiting...');
      continue;
    }

    final json = logFile.readAsStringSync();

    if (isVerbose) {
      log.info(json);
    }

    final decoded = jsonDecode(json);
    if (decoded['status'] == 'Accepted') {
      log.info('Notarized');
      return true;
    } else {
      log.warning('Notarize error with message: ${decoded['statusSummary']}');
      log.warning('Look at ${logFile.path} for more details');
      return false;
    }
  } while (true);
}
