import 'dart:convert' show JsonEncoder, json;
import 'dart:io' show File;
import 'dart:ui' show ImageFilter;

import 'package:bson/bson.dart' show BsonBinary, BsonCodec;
import 'package:file_picker/file_picker.dart' show FilePicker;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart'
    show useTextEditingController, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show HookConsumerWidget, WidgetRef;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/src/state/provider.dart' show directoriesProvider;
import 'package:tts_mod_vault/src/utils.dart' show showSnackBar;

class DownloadModByIdDialog extends HookConsumerWidget {
  const DownloadModByIdDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetDirectory =
        useState(p.normalize(ref.read(directoriesProvider).workshopDir));
    final downloading = useState(false);
    final textController = useTextEditingController();

    Future<void> downloadAndResizeImage(String imageUrl, String modId) async {
      try {
        // Download the image
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode != 200) {
          debugPrint('Failed to download image');
          return;
        }

        // Decode the image
        final originalImage = img.decodeImage(response.bodyBytes);
        if (originalImage == null) {
          debugPrint('Failed to decode image');
          return;
        }

        // First save the original at maximum quality
        final tempPath = '${targetDirectory.value}/${modId}_temp.png';
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(img.encodePng(
          originalImage,
          level: 0,
        ));

        // Read back the uncompressed image
        final uncompressedBytes = await tempFile.readAsBytes();
        final uncompressedImage = img.decodeImage(uncompressedBytes);
        if (uncompressedImage == null) {
          debugPrint('Failed to decode uncompressed image');
          return;
        }

        // Now resize from the uncompressed version
        final resizedImage = img.copyResizeCropSquare(
          uncompressedImage,
          size: 256,
          interpolation: img.Interpolation.cubic,
        );

        // Save the final resized image with minimal compression
        final finalPath = '${targetDirectory.value}/$modId.png';
        final finalFile = File(finalPath);

        await finalFile.writeAsBytes(img.encodePng(
          resizedImage,
          level: 0, // Keep using no compression for best quality
        ));

        // Clean up temp file
        await tempFile.delete();

        debugPrint('Image saved to: $finalPath');
      } catch (e) {
        debugPrint('Error processing image: $e');
      }
    }

    Future<void> downloadAndConvertBson(String fileUrl, String modId) async {
      try {
        final response = await http.get(Uri.parse(fileUrl));
        if (response.statusCode != 200) {
          debugPrint('Failed to download BSON file');
          return;
        }

        final bsonBinary = BsonBinary.from(response.bodyBytes);
        final decodedData = BsonCodec.deserialize(bsonBinary);

        // Convert to pretty-printed JSON
        final jsonString =
            const JsonEncoder.withIndent('  ').convert(decodedData);

        final filePath = '${targetDirectory.value}/$modId.json';
        final file = File(filePath);

        await file.writeAsString(jsonString);
        debugPrint('JSON saved to: $filePath');
      } catch (e) {
        debugPrint('Error processing BSON file: $e');
      }
    }

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: AlertDialog(
        content: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            Text(
              'Download Workshop Mod by ID',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            TextField(
              controller: textController,
              cursorColor: Colors.black,
              keyboardType: TextInputType.number,
              style:
                  TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                fillColor: Colors.white,
                border: OutlineInputBorder(),
                hintText: 'Enter ID',
              ),
            ),
            Text('Save to: ${targetDirectory.value}'),
            Row(
              spacing: 8,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: downloading.value
                      ? null
                      : () async {
                          String? dir;
                          final initialDirectory = p.normalize(
                              ref.read(directoriesProvider).workshopDir);

                          try {
                            dir = await FilePicker.platform.getDirectoryPath(
                              lockParentWindow: true,
                              initialDirectory: initialDirectory,
                            );
                          } catch (e) {
                            debugPrint("File picker error $e");
                            if (context.mounted) {
                              showSnackBar(
                                  context, "Failed to open file picker");
                              Navigator.pop(context);
                            }
                            return;
                          }

                          if (dir == null) return;

                          targetDirectory.value = p.normalize(dir);
                        },
                  child: Text('Select folder'),
                ),
                Spacer(),
                ElevatedButton(
                  onPressed: downloading.value
                      ? null
                      : () {
                          Navigator.of(context).pop();
                        },
                  child: const Text('Cancel'),
                ),
                ElevatedButton.icon(
                  onPressed: downloading.value
                      ? null
                      : () async {
                          try {
                            final modId = textController.text;
                            if (textController.text.isEmpty) {
                              return;
                            }

                            downloading.value = true;

                            final url = Uri.parse(
                              'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/',
                            );

                            final response = await http.post(
                              url,
                              body: {
                                'itemcount': '1',
                                'publishedfileids[0]': modId.toString(),
                              },
                            );

                            final responseData = json.decode(response.body);

                            final fileDetails = responseData['response']
                                ['publishedfiledetails'][0];

                            final consumerAppId =
                                fileDetails['consumer_app_id'];
                            if (consumerAppId == 286160) {
                              final fileUrl = fileDetails['file_url'];
                              final previewUrl = fileDetails['preview_url'];

                              await downloadAndConvertBson(fileUrl, modId);
                              await downloadAndResizeImage(previewUrl, modId);
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            } else {
                              debugPrint(
                                  'Consumer app ID does not match. Expected: 286160, Got: $consumerAppId');
                            }
                          } catch (e) {
                            debugPrint('Error: $e');

                            // TODO add show snackbar for errors
                          } finally {
                            downloading.value = false;
                          }
                        },
                  icon: Icon(Icons.download),
                  label: const Text('Download'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
