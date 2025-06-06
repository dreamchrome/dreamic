part of 'cubit_base.dart';

class CubitBaseState extends Equatable {
  const CubitBaseState({
    this.pageStatus = PageStatus.loading,
  });

  final PageStatus pageStatus;

  CubitBaseState copyWith({
    PageStatus? pageStatus,
  }) {
    return CubitBaseState(
      pageStatus: pageStatus ?? this.pageStatus,
    );
  }

  @override
  List<Object?> get props => [
        pageStatus,
      ];
}
