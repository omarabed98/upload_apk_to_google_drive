# Flutter APK Upload Automation

This project automates the process of building a Flutter APK, uploading it to Google Drive, and sending a notification to Slack. This README provides the necessary steps to set up the required Google API and Slack API credentials, configure Dart dependencies, and run the automation scripts.

## Table of Contents

1. [Introduction](#introduction)
2. [Setup Google API](#setup-google-api)
3. [Setup Slack API](#setup-slack-api)
4. [Configure Dart Dependencies](#configure-dart-dependencies)
5. [Create Dart File](#create-dart-file)
6. [Create Shell Script](#create-shell-script)
7. [Running the Script](#running-the-script)
8. [Tags](#tags)
9. [Notes](#notes)

## Introduction

This project is designed to streamline the process of deploying Flutter applications by automating APK builds, uploads to Google Drive, and notifications via Slack. It is ideal for teams looking to integrate these steps into a CI/CD pipeline or automate them for regular releases.

## Setup Google API

1. **Create a Project in Google Cloud Console:**
   - Navigate to the [Google Cloud Console](https://console.cloud.google.com/).
   - Create a new project or select an existing one.

2. **Enable Google Drive API:**
   - Go to `APIs & Services` > `Library`.
   - Search for "Google Drive API" and enable it.

3. **Create OAuth 2.0 Credentials:**
   - Go to `APIs & Services` > `Credentials`.
   - Click on `Create Credentials` and select `OAuth 2.0 Client ID`.
   - Configure the consent screen and set the application type to `Desktop app`.
   - Download the JSON file containing your credentials and rename it to `credentials.json`.

4. **Save your `credentials.json` file:**
   - Place the `credentials.json` file in the root of your project directory.

## Setup Slack API

1. **Create a Slack App:**
   - Go to the [Slack API page](https://api.slack.com/apps).
   - Click on `Create New App` and choose `From scratch`.
   - Provide a name and select a workspace.

2. **Configure Incoming Webhooks:**
   - In the app settings, navigate to `Incoming Webhooks`.
   - Activate incoming webhooks and create a new webhook URL for your workspace.
   - Copy the webhook URL; you'll use this in the Dart code.

## Configure Dart Dependencies

Add the following dependencies to your `pubspec.yaml` file:

```yaml
dependencies:
  googleapis: ^13.2.0
  googleapis_auth: ^1.1.0
  http: ^0.14.0
```

Run the following command to install the packages:

```bash
flutter pub get
```

## Create Dart File

Create a Dart file named `upload_apk_to_google_drive.dart` with the following content:

```dart

import 'dart:convert';
import 'dart:io';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

// Load OAuth 2.0 client credentials from the JSON file
Future<Map<String, dynamic>> loadCredentials() async {
  final file = File('credentials.json'); // OAuth 2.0 credentials file
  final contents = await file.readAsString();
  return json.decode(contents);
}

Future<void> saveTokens(AccessCredentials credentials) async {
  final file = File('tokens.json');
  await file.writeAsString(jsonEncode(credentials.toJson()));
}

Future<AccessCredentials?> loadTokens() async {
  try {
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
  const webhookUrl = 'YOUR_SLACK_WEBHOOK_URL';
  final message = {
    'text':
        'APK has been built and uploaded! [Download here](https://drive.google.com/file/d/${response.id}/view?usp=sharing)'
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

// Define MyApp and MyHomePage widgets as needed.
```

## Create Shell Script

Create a file named `release_apk.sh` with the following content:

```bash
#!/bin/bash

# Build the APK
flutter build apk

# Run the Dart script to upload to Google Drive and send Slack message
dart run lib/upload_apk_to_google_drive.dart
```

## Running the Script

1. Make the script executable:

    ```bash
    chmod +x release_apk.sh
    ```

2. Run the script:

    ```bash
    ./release_apk.sh
    ```

## Tags

- Flutter
- Google Drive API
- Slack API
- Dart
- Automation
- APK Release
- API Integration
- Google API Credentials
- Slack Webhook
- Shell Script
- Flutter Deployment
- CI/CD
- App Release Automation

## Notes

- Ensure that `YOUR_SLACK_WEBHOOK_URL` is replaced with your actual Slack webhook URL in the Dart file.
- Adjust any file paths as necessary based on your project's directory structure.

---

This README should provide a clear and comprehensive guide to setting up and using the Flutter APK upload automation project. Let me know if you need further details or modifications.
