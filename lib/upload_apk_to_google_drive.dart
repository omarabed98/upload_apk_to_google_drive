import 'dart:convert';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// Load OAuth 2.0 client credentials from the JSON file
Future<Map<String, dynamic>> loadCredentials() async {
  // Download credentials.json from Google Cloud
  final file = File('credentials.json'); // OAuth 2.0 credentials file

  // Note: For security reasons, this file will be deleted and not committed to the repository.
  // You can refer to the "Setup Google API" section in the README file to learn how to download this file.
  final contents = await file.readAsString();
  return json.decode(contents);
}

Future<void> saveTokens(AccessCredentials credentials) async {
  // The tokens.json file is used to store OAuth 2.0 tokens for future use.
  // This file will store access and refresh tokens after the first successful authentication.
  // Note: For security reasons, this file should not be committed to the repository.

  final file = File('tokens.json');
  await file.writeAsString(jsonEncode(credentials.toJson()));
}

Future<AccessCredentials?> loadTokens() async {
  try {
    // The tokens.json file is used to retrieve stored OAuth 2.0 tokens.
    // Note: For security reasons, this file should not be committed to the repository.

    final file = File('tokens.json');
    final contents = await file.readAsString();
    return AccessCredentials.fromJson(jsonDecode(contents));
  } catch (e) {
    return null; // If the file doesn't exist or there's an error, return null
  }
}

Future<String> getFolderId(drive.DriveApi driveApi, String folderName,
    {String? parentFolderId}) async {
  try {
    final query =
        "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder'${parentFolderId != null ? " and '$parentFolderId' in parents" : ""}";
    final fileList = await driveApi.files.list(q: query);

    if (fileList.files != null && fileList.files!.isNotEmpty) {
      return fileList.files!.first.id!;
    }

    // Folder not found, create it
    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = parentFolderId != null ? [parentFolderId] : null;

    final folderCreationResponse = await driveApi.files.create(folder);
    return folderCreationResponse.id!;
  } catch (e) {
    print('Failed to get or create folder: $e');
    rethrow;
  }
}

Future<void> uploadToGoogleDrive() async {
  // Load OAuth 2.0 client credentials
  final credentials = await loadCredentials();
  final clientId = ClientId(credentials['installed']['client_id'],
      credentials['installed']['client_secret']);

  AccessCredentials? accessCredentials = await loadTokens();

  AuthClient? authenticatedClient;

  if (accessCredentials == null || accessCredentials.accessToken.hasExpired) {
    authenticatedClient = await clientViaUserConsent(
        clientId, [drive.DriveApi.driveFileScope], (url) {
      print('Please go to the following URL and grant access:');
      print('  => $url');
    });

    accessCredentials = authenticatedClient.credentials;

    await saveTokens(accessCredentials); // Save the new tokens
  } else {
    authenticatedClient =
        autoRefreshingClient(clientId, accessCredentials, http.Client());
  }

  // Create Google Drive API instance
  final driveApi = drive.DriveApi(authenticatedClient);

  // Get the Development folder ID, creating it if necessary
  final developmentFolderId = await getFolderId(driveApi, 'Apk');

  // Define your app name
  const appName = 'MyAppName'; // Replace with your actual app name

  // Get the AppName subfolder ID, creating it if necessary
  final appFolderId =
      await getFolderId(driveApi, appName, parentFolderId: developmentFolderId);

  // Get the current date folder ID, creating it if necessary
  final currentDate = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final dateFolderId =
      await getFolderId(driveApi, currentDate, parentFolderId: appFolderId);

  // Format the file name with the current time
  final currentTime = DateFormat('hh:mm a').format(DateTime.now());
  final fileName = '$appName-$currentTime.apk';

  // Upload file to Google Drive in the date folder
  final fileToUpload = File('build/app/outputs/flutter-apk/app-release.apk');
  final media = drive.Media(fileToUpload.openRead(), fileToUpload.lengthSync());

  final driveFile = drive.File()
    ..name = fileName
    ..parents = [dateFolderId]; // Specify the date subfolder ID here

  final response = await driveApi.files.create(driveFile, uploadMedia: media);
  print('File uploaded. File ID: ${response.id}');

  // Set file permissions to "anyone with the link"
  final permission = drive.Permission()
    ..type = 'anyone'
    ..role = 'reader';

  await driveApi.permissions.create(permission, response.id!);
  print('Permissions set to anyone with the link.');

  // Send Slack message
  const webhookUrl =
      'https://hooks.slack.com/services/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';

  final String currentDateTime =
      DateFormat('EEE dd MMM hh:mm a yyyy').format(DateTime.now());

  final message = {
    'text': '''
------------------------------------------------------------------
*Subject: New APK Release Notification*

Dear Team,

I hope this message finds you well.

I would like to inform you that a new version of the APK has been successfully built and uploaded as of *$currentDateTime*. You can download the updated APK using the following link:

<https://drive.google.com/file/d/${response.id}/view?usp=sharing|Download New APK>

Kindly review the new version at your earliest convenience. Your feedback is invaluable to us, so please conduct thorough testing and let me know if there are any issues or further modifications needed. Your time and effort in this testing phase are greatly appreciated.

Thank you very much for your attention to this matter and for your continued cooperation.

Best regards,

Omar Abed  
Flutter Developer  

<tel:00962791300360|00962791300360>  
<mailto:oabed7860@gmail.com|oabed7860@gmail.com>  
<mailto:omar.a82@yahoo.com|omar.a82@yahoo.com>
  ''',
    'design': '''
────────────────────────────
          *New APK Release*
────────────────────────────
  '''
  };

  final slackResponse = await http.post(
    Uri.parse(webhookUrl),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(message),
  );

  if (slackResponse.statusCode == 200) {
    print('Slack message sent successfully.');
  } else {
    print('Failed to send Slack message: ${slackResponse.body}');
  }
}

void main() async {
  final buildResult = await Process.run('flutter', ['build', 'apk']);
  if (buildResult.exitCode != 0) {
    print('Failed to build APK: ${buildResult.stderr}');
    return;
  }
  print('APK built successfully.');

  // Upload to Google Drive and send Slack message
  await uploadToGoogleDrive();
}
