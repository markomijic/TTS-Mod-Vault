enum CleanUpStatusEnum {
  idle,
  scanning,
  awaitingConfirmation,
  deleting,
  completed,
  error,
}

class CleanUpState {
  final CleanUpStatusEnum status;
  final List<String> filesToDelete;

  final String? errorMessage;

  const CleanUpState({
    this.status = CleanUpStatusEnum.idle,
    this.filesToDelete = const [],
    this.errorMessage,
  });

  CleanUpState copyWith({
    CleanUpStatusEnum? status,
    List<String>? filesToDelete,
    String? errorMessage,
  }) {
    return CleanUpState(
      status: status ?? this.status,
      filesToDelete: filesToDelete ?? this.filesToDelete,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
