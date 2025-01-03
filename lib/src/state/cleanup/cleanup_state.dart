enum CleanupStatus {
  idle,
  scanning,
  awaitingConfirmation,
  deleting,
  completed,
  error,
}

class CleanupState {
  final CleanupStatus status;
  final List<String> filesToDelete;

  final String? errorMessage;

  const CleanupState({
    this.status = CleanupStatus.idle,
    this.filesToDelete = const [],
    this.errorMessage,
  });

  CleanupState copyWith({
    CleanupStatus? status,
    List<String>? filesToDelete,
    String? errorMessage,
  }) {
    return CleanupState(
      status: status ?? this.status,
      filesToDelete: filesToDelete ?? this.filesToDelete,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
