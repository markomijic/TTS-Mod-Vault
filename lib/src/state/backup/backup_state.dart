import 'dart:isolate' show SendPort;

enum BackupStatusEnum {
  idle,
  awaitingBackupFolder,
  backingUp,
}

class BackupState {
  final BackupStatusEnum status;
  final int totalCount;
  final int currentCount;
  final String message;

  const BackupState({
    this.status = BackupStatusEnum.idle,
    this.totalCount = 0,
    this.currentCount = 0,
    this.message = "",
  });

  BackupState copyWith({
    BackupStatusEnum? status,
    int? totalCount,
    int? currentCount,
    String? message,
  }) {
    return BackupState(
      status: status ?? this.status,
      totalCount: totalCount ?? this.totalCount,
      currentCount: currentCount ?? this.currentCount,
      message: message ?? this.message,
    );
  }
}

// Message types for isolate communication
abstract class BackupMessage {}

class BackupProgressMessage extends BackupMessage {
  final int current;
  final int total;

  BackupProgressMessage(this.current, this.total);
}

class BackupCompleteMessage extends BackupMessage {
  final bool success;
  final String message;

  BackupCompleteMessage(this.success, this.message);
}

// Data to send to isolate
class BackupIsolateData {
  final List<String> filePaths;
  final String targetBackupFilePath;
  final String modsParentPath;
  final String savesParentPath;
  final String savesPath;
  final SendPort sendPort;

  BackupIsolateData({
    required this.filePaths,
    required this.targetBackupFilePath,
    required this.modsParentPath,
    required this.savesParentPath,
    required this.savesPath,
    required this.sendPort,
  });
}
