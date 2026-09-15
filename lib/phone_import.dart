import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'trial_credentials.dart';

/// The only two kinds of media that can enter the private Content Doctor
/// library from a phone.  The server, not the client, remains the authority
/// on format inspection and final intake.
enum PhoneImportKind { video, audio }

extension PhoneImportKindText on PhoneImportKind {
  String get label => this == PhoneImportKind.video ? 'Video' : 'Audio';

  List<String> get extensions => this == PhoneImportKind.video
      ? const <String>['mp4', 'mov', 'm4v', 'webm']
      : const <String>['mp3', 'm4a', 'wav', 'aac'];

  String get mimeType =>
      this == PhoneImportKind.video ? 'video/mp4' : 'audio/mpeg';
}

/// A concise, safe receipt returned after Content Doctor accepts an import.
class PhoneImportReceipt {
  const PhoneImportReceipt({
    required this.kind,
    required this.message,
    required this.item,
  });

  final PhoneImportKind kind;
  final String message;
  final Map<String, dynamic> item;

  factory PhoneImportReceipt.fromJson(dynamic value) {
    if (value is! Map || value['ok'] != true || value['item'] is! Map) {
      throw const FormatException('The import was not confirmed.');
    }
    final String rawKind = '${value['kind'] ?? ''}'.toLowerCase();
    final PhoneImportKind kind = switch (rawKind) {
      'video' => PhoneImportKind.video,
      'audio' => PhoneImportKind.audio,
      _ => throw const FormatException(
        'The import returned an unknown file type.',
      ),
    };
    final String message = '${value['message'] ?? ''}'.trim();
    return PhoneImportReceipt(
      kind: kind,
      message: message.isEmpty
          ? '${kind.label} added to your library.'
          : message,
      item: Map<String, dynamic>.from(value['item'] as Map),
    );
  }
}

/// Limits are checked before a network request.  Server-side checks must keep
/// the same limit, because a client cannot be trusted to enforce it.
const int phoneImportMaxBytes = 250 * 1024 * 1024;

String? phoneImportValidationMessage({
  required String account,
  required PhoneImportKind kind,
  required String name,
  required int bytes,
}) {
  final String typeName = kind.label.toLowerCase();
  final String article = kind == PhoneImportKind.audio ? 'an' : 'a';
  if (account.trim().isEmpty) return 'Choose an account first.';
  if (name.trim().isEmpty) return 'Choose $article $typeName file.';
  if (bytes <= 0) return 'That file is empty.';
  if (bytes > phoneImportMaxBytes) return 'Choose a file smaller than 250 MB.';
  final String extension = name.split('.').last.toLowerCase();
  if (!kind.extensions.contains(extension)) {
    return 'Choose $article $typeName file.';
  }
  return null;
}

String _safeName(String value) =>
    value.replaceAll(RegExp(r'[\r\n]'), '').replaceAll('"', '').trim();

String _mediaType(PhoneImportKind kind, String name) {
  final String extension = name.split('.').last.toLowerCase();
  return switch (extension) {
    'mov' => 'video/quicktime',
    'm4v' => 'video/x-m4v',
    'webm' => 'video/webm',
    'm4a' => 'audio/mp4',
    'wav' => 'audio/wav',
    'aac' => 'audio/aac',
    _ => kind.mimeType,
  };
}

/// Owns one streaming upload. [cancel] immediately closes the underlying
/// socket; it never reads an entire clip into application memory.
class PhoneImportTask {
  PhoneImportTask();

  HttpClient? _client;
  bool _cancelled = false;

  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<PhoneImportReceipt> upload({
    required String base,
    required String account,
    required PhoneImportKind kind,
    required PlatformFile file,
    ValueChanged<double>? onProgress,
  }) async {
    final String? validation = phoneImportValidationMessage(
      account: account,
      kind: kind,
      name: file.name,
      bytes: await file.length(),
    );
    if (validation != null) throw FormatException(validation);
    if (_cancelled) throw const _PhoneImportCancelled();

    final String filename = _safeName(file.name);
    final int length = await file.length();
    final String boundary =
        'content-doctor-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(this)}';
    final List<int> accountPart = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="account"\r\n\r\n'
      '${account.trim()}\r\n',
    );
    final List<int> kindPart = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="kind"\r\n\r\n'
      '${kind.name}\r\n',
    );
    final List<int> fileHeader = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="file"; filename="$filename"\r\n'
      'Content-Type: ${_mediaType(kind, filename)}\r\n\r\n',
    );
    final List<int> tail = utf8.encode('\r\n--$boundary--\r\n');

    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    _client = client;
    try {
      final HttpClientRequest request = await client.postUrl(
        Uri.parse('$base/reels/import'),
      );
      await TrialCredentials.attach(request, base);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      request.contentLength =
          accountPart.length +
          kindPart.length +
          fileHeader.length +
          length +
          tail.length;
      request.add(accountPart);
      request.add(kindPart);
      request.add(fileHeader);

      int transferred = 0;
      int lastProgressPercent = -1;
      final Stream<List<int>> stream = file.readAsByteStream().transform(
        StreamTransformer<Uint8List, List<int>>.fromHandlers(
          handleData: (Uint8List chunk, EventSink<List<int>> sink) {
            if (_cancelled) {
              sink.addError(const _PhoneImportCancelled());
              return;
            }
            transferred += chunk.length;
            final int percent = (transferred * 100 ~/ length).clamp(0, 100);
            if (percent != lastProgressPercent) {
              lastProgressPercent = percent;
              onProgress?.call(percent / 100);
            }
            sink.add(chunk);
          },
        ),
      );
      await request.addStream(stream).timeout(const Duration(minutes: 3));
      if (_cancelled) throw const _PhoneImportCancelled();
      request.add(tail);
      final HttpClientResponse response = await request.close().timeout(
        const Duration(minutes: 3),
      );
      final String body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 20));
      dynamic decoded;
      try {
        decoded = body.isEmpty ? null : jsonDecode(body);
      } on FormatException {
        decoded = null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final String detail = decoded is Map
            ? '${decoded['detail'] ?? decoded['error'] ?? ''}'.trim()
            : '';
        throw HttpException(
          detail.isEmpty ? 'Import could not be completed. Try again.' : detail,
        );
      }
      return PhoneImportReceipt.fromJson(decoded);
    } on _PhoneImportCancelled {
      rethrow;
    } on TimeoutException {
      throw const HttpException('Import timed out. Try again.');
    } finally {
      _client = null;
      client.close(force: true);
    }
  }
}

class _PhoneImportCancelled implements Exception {
  const _PhoneImportCancelled();
}

/// Opens a focused native import sheet and returns its confirmed receipt.
///
/// [accounts] must already be role-scoped by the caller.  A returned null
/// means the person simply dismissed the sheet; it is not an upload result.
Future<PhoneImportReceipt?> showPhoneImport({
  required BuildContext context,
  required String base,
  required List<String> accounts,
  String? initialAccount,
}) => showModalBottomSheet<PhoneImportReceipt>(
  context: context,
  isScrollControlled: true,
  backgroundColor: SandDark.surfaceLow,
  constraints: const BoxConstraints(maxWidth: SandLayout.sheet),
  builder: (BuildContext context) => _PhoneImportSheet(
    base: base,
    accounts: accounts,
    initialAccount: initialAccount,
  ),
);

class _PhoneImportSheet extends StatefulWidget {
  const _PhoneImportSheet({
    required this.base,
    required this.accounts,
    this.initialAccount,
  });

  final String base;
  final List<String> accounts;
  final String? initialAccount;

  @override
  State<_PhoneImportSheet> createState() => _PhoneImportSheetState();
}

class _PhoneImportSheetState extends State<_PhoneImportSheet> {
  PhoneImportTask? _task;
  String? _status;
  double? _progress;
  bool _picking = false;
  late String? _account = widget.accounts.contains(widget.initialAccount)
      ? widget.initialAccount
      : (widget.accounts.isEmpty ? null : widget.accounts.first);

  bool get _busy => _picking || _task != null;

  Future<void> _pickAndImport(PhoneImportKind kind) async {
    setState(() {
      _picking = true;
      _status = null;
    });
    try {
      final PlatformFile? file = await FilePicker.pickFile(
        dialogTitle: 'Choose ${kind.label.toLowerCase()}',
        // FileType.video opens the native iOS Photos picker, not a Files-only
        // document sheet. Audio intentionally uses Files because Photos has
        // no audio-library picker.
        type: kind == PhoneImportKind.video ? FileType.video : FileType.audio,
        compressionQuality: 0,
        darwinOptions: const DarwinOptions(
          assetRepresentationMode: DarwinAssetRepresentationMode.current,
        ),
      );
      if (file == null || !mounted) return;
      final PhoneImportTask task = PhoneImportTask();
      setState(() {
        _picking = false;
        _task = task;
        _progress = 0;
        _status = 'Adding ${kind.label.toLowerCase()}…';
      });
      final PhoneImportReceipt receipt = await task.upload(
        base: widget.base,
        account: _account ?? '',
        kind: kind,
        file: file,
        onProgress: (double value) {
          if (mounted && identical(_task, task)) {
            setState(() => _progress = value);
          }
        },
      );
      if (!mounted || !identical(_task, task)) return;
      Navigator.of(context).pop(receipt);
    } on _PhoneImportCancelled {
      if (mounted) {
        setState(
          () => _status = 'Import stopped. Refresh before trying again.',
        );
      }
    } on Object catch (error) {
      if (mounted) setState(() => _status = _importMessage(error));
    } finally {
      if (mounted) {
        setState(() {
          _picking = false;
          _task = null;
          _progress = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _task?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            SandSpace.x5,
            SandSpace.x4,
            SandSpace.x5,
            MediaQuery.viewInsetsOf(context).bottom + SandSpace.x5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  height: 4,
                  width: 34,
                  decoration: BoxDecoration(
                    color: SandDark.outlineStrong,
                    borderRadius: BorderRadius.circular(SandRadius.pill),
                  ),
                ),
              ),
              const SizedBox(height: SandSpace.x5),
              Text(
                'Add from phone',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: SandSpace.x1),
              DropdownButtonFormField<String>(
                initialValue: _account,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Account'),
                items: widget.accounts
                    .map(
                      (String account) => DropdownMenuItem<String>(
                        value: account,
                        child: Text(account, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (String? value) => setState(() => _account = value),
              ),
              if (_account == null) ...<Widget>[
                const SizedBox(height: SandSpace.x2),
                Text(
                  'No account is available yet.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: SandDark.onSurfaceLow),
                ),
              ],
              const SizedBox(height: SandSpace.x5),
              FilledButton.icon(
                onPressed: _busy || _account == null
                    ? null
                    : () => _pickAndImport(PhoneImportKind.video),
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Choose video'),
              ),
              const SizedBox(height: SandSpace.x3),
              OutlinedButton.icon(
                onPressed: _busy || _account == null
                    ? null
                    : () => _pickAndImport(PhoneImportKind.audio),
                icon: const Icon(Icons.audio_file_outlined),
                label: const Text('Choose audio'),
              ),
              if (_progress != null) ...<Widget>[
                const SizedBox(height: SandSpace.x5),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: SandSpace.x2),
              ],
              if (_status != null) ...<Widget>[
                const SizedBox(height: SandSpace.x2),
                Text(
                  _status!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: SandDark.onSurfaceLow),
                ),
              ],
              if (_task != null) ...<Widget>[
                const SizedBox(height: SandSpace.x2),
                TextButton(
                  onPressed: _task!.cancel,
                  child: const Text('Cancel import'),
                ),
              ],
              const SizedBox(height: SandSpace.x2),
              Text(
                'Up to 250 MB. New files stay private until review.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SandDark.onSurfaceLowest,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _importMessage(Object error) {
  if (error is FormatException) {
    final String text = error.message.toString().trim();
    return text.isEmpty ? 'Import could not be completed. Try again.' : text;
  }
  if (error is HttpException) {
    final String text = error.message.trim();
    return text.isEmpty ? 'Import could not be completed. Try again.' : text;
  }
  return 'Import could not be completed. Try again.';
}
