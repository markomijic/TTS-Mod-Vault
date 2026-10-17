/// Steam Web API client for Workshop items: `GetPublishedFileDetails` and
/// raw file downloads. Replaces v2's untyped JSON access and its
/// exception-text classification of unlisted / missing items.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/domain/constants.dart';

/// Why a Workshop item can or cannot be downloaded.
enum WorkshopItemStatus {
  /// Listed, belongs to the expected app, has a file URL.
  ok,

  /// Steam does not know the id (`result != 1`, typically 9).
  notFound,

  /// Steam knows the id but exposes no file or timestamp: the item is
  /// unlisted, private or removed.
  unlisted,

  /// The item belongs to another game.
  wrongApp,

  /// The response entry could not be parsed.
  invalid;

  /// Whether the item can be downloaded.
  bool get isOk => this == ok;
}

/// One entry of a `GetPublishedFileDetails` response, parsed defensively:
/// every field but [id] and [result] may be missing.
final class WorkshopItemDetails {
  /// Creates details.
  const WorkshopItemDetails({
    required this.id,
    required this.result,
    this.title,
    this.fileUrl,
    this.previewUrl,
    this.timeUpdated,
    this.consumerAppId,
  });

  /// Parses one `publishedfiledetails` entry; [fallbackId] is used when the
  /// entry carries no `publishedfileid`.
  factory WorkshopItemDetails.fromJson(
    Map<String, Object?> json, {
    String fallbackId = '',
  }) => WorkshopItemDetails(
    id: _string(json['publishedfileid']) ?? fallbackId,
    result: _int(json['result']) ?? 0,
    title: _string(json['title']),
    fileUrl: _nonEmpty(_string(json['file_url'])),
    previewUrl: _nonEmpty(_string(json['preview_url'])),
    timeUpdated: _int(json['time_updated']),
    consumerAppId: _int(json['consumer_app_id']),
  );

  /// Details for an id Steam left out of its answer.
  factory WorkshopItemDetails.missing(String id) =>
      WorkshopItemDetails(id: id, result: 0);

  /// Details for an id whose lookup failed altogether (network error,
  /// malformed response); classified as [WorkshopItemStatus.invalid].
  factory WorkshopItemDetails.lookupFailed(String id) =>
      WorkshopItemDetails(id: id, result: -1);

  /// The Workshop id.
  final String id;

  /// Steam's per-item result code; 1 means success, 9 not found. `-1` is
  /// this app's marker for a failed lookup ([WorkshopItemDetails.lookupFailed]).
  final int result;

  /// The item's title.
  final String? title;

  /// URL of the item's file (the BSON save).
  final String? fileUrl;

  /// URL of the preview image.
  final String? previewUrl;

  /// Last update, Unix seconds.
  final int? timeUpdated;

  /// Steam app id the item belongs to.
  final int? consumerAppId;

  /// Classifies the item for [appId] (Tabletop Simulator by default).
  WorkshopItemStatus statusFor({int appId = tabletopSimulatorAppId}) {
    if (result < 0) return WorkshopItemStatus.invalid;
    if (result != 1) return WorkshopItemStatus.notFound;
    if (consumerAppId != null && consumerAppId != appId) {
      return WorkshopItemStatus.wrongApp;
    }
    if (fileUrl == null || timeUpdated == null) {
      return WorkshopItemStatus.unlisted;
    }
    if (consumerAppId == null) return WorkshopItemStatus.wrongApp;
    return WorkshopItemStatus.ok;
  }

  static String? _string(Object? value) => switch (value) {
    final String s => s,
    final num n => n.toString(),
    _ => null,
  };

  static int? _int(Object? value) => switch (value) {
    final int i => i,
    final num n => n.toInt(),
    final String s => int.tryParse(s),
    _ => null,
  };

  static String? _nonEmpty(String? value) =>
      value == null || value.isEmpty ? null : value;

  @override
  String toString() =>
      'WorkshopItemDetails($id result=$result title=$title '
      'app=$consumerAppId updated=$timeUpdated)';
}

/// Thrown when the details endpoint does not answer with a well-formed
/// response (network error, non-200 status, unexpected JSON shape).
final class SteamWorkshopException implements Exception {
  /// Creates the exception.
  const SteamWorkshopException(this.message, {this.cause});

  /// What went wrong.
  final String message;

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() => 'SteamWorkshopException: $message';
}

/// Talks to the Steam Web API and the Steam CDN.
final class SteamWorkshopClient {
  /// Creates a client. [apiUrl] is the `GetPublishedFileDetails` endpoint.
  SteamWorkshopClient({
    required this.dio,
    this.apiUrl = steamPublishedFileDetailsUrl,
  });

  /// Ids per `GetPublishedFileDetails` call.
  static const int idsPerRequest = 100;

  /// The HTTP client.
  final Dio dio;

  /// The details endpoint.
  final String apiUrl;

  /// Fetches the details of [ids] (in chunks of [idsPerRequest]) and
  /// returns one entry per id, in the order given. Ids Steam leaves out of
  /// its answer come back as [WorkshopItemDetails.missing]. Throws
  /// [SteamWorkshopException] when a request fails or the response has an
  /// unexpected shape, [OperationCancelledException] when [token] is
  /// cancelled.
  Future<List<WorkshopItemDetails>> getPublishedFileDetails(
    List<String> ids, {
    CancellationToken? token,
  }) async {
    final cleaned = [
      for (final id in ids)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    if (cleaned.isEmpty) return const [];
    final byId = <String, WorkshopItemDetails>{};
    for (var start = 0; start < cleaned.length; start += idsPerRequest) {
      final chunk = cleaned.sublist(
        start,
        start + idsPerRequest > cleaned.length
            ? cleaned.length
            : start + idsPerRequest,
      );
      for (final details in await _fetchChunk(chunk, token)) {
        byId[details.id] = details;
      }
    }
    return [
      for (final id in cleaned) byId[id] ?? WorkshopItemDetails.missing(id),
    ];
  }

  Future<List<WorkshopItemDetails>> _fetchChunk(
    List<String> ids,
    CancellationToken? token,
  ) async {
    final cancelToken = CancelToken();
    final unlisten = token?.onCancel(cancelToken.cancel) ?? () {};
    try {
      final response = await dio.post<String>(
        apiUrl,
        data: {
          'itemcount': '${ids.length}',
          for (var i = 0; i < ids.length; i++) 'publishedfileids[$i]': ids[i],
        },
        cancelToken: cancelToken,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );
      final body = response.data;
      if (body == null || body.isEmpty) {
        throw const SteamWorkshopException('Steam returned an empty response');
      }
      return _parse(body, ids);
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        throw OperationCancelledException(token?.cancelReason);
      }
      final status = error.response?.statusCode;
      throw SteamWorkshopException(
        status == null
            ? 'Could not reach the Steam Web API: ${error.message}'
            : 'Steam Web API answered $status',
        cause: error,
      );
    } finally {
      unlisten();
    }
  }

  static List<WorkshopItemDetails> _parse(String body, List<String> ids) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw SteamWorkshopException(
        'Steam returned malformed JSON',
        cause: error,
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const SteamWorkshopException('Unexpected Steam response shape');
    }
    final response = decoded['response'];
    if (response is! Map<String, Object?>) {
      throw const SteamWorkshopException(
        'Steam response has no "response" object',
      );
    }
    final entries = response['publishedfiledetails'];
    if (entries is! List) {
      // Steam answers this way when every id is unknown.
      return const [];
    }
    final result = <WorkshopItemDetails>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final fallbackId = i < ids.length ? ids[i] : '';
      if (entry is Map<String, Object?>) {
        result.add(WorkshopItemDetails.fromJson(entry, fallbackId: fallbackId));
      } else if (fallbackId.isNotEmpty) {
        result.add(WorkshopItemDetails(id: fallbackId, result: 0));
      }
    }
    return result;
  }

  /// Downloads [url] (a Workshop file or preview image) into memory.
  /// Throws [DioException] on HTTP or network errors,
  /// [OperationCancelledException] when [token] is cancelled.
  Future<Uint8List> download(String url, {CancellationToken? token}) async {
    final cancelToken = CancelToken();
    final unlisten = token?.onCancel(cancelToken.cancel) ?? () {};
    try {
      final response = await dio.get<List<int>>(
        url,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      final data = response.data;
      if (data == null) return Uint8List(0);
      return data is Uint8List ? data : Uint8List.fromList(data);
    } on DioException catch (error) {
      if (error.type == DioExceptionType.cancel) {
        throw OperationCancelledException(token?.cancelReason);
      }
      rethrow;
    } finally {
      unlisten();
    }
  }
}
