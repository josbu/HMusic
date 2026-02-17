class SearchOutcome<T> {
  final List<T> results;
  final SearchErrorType errorType;
  final String? message;

  const SearchOutcome({
    required this.results,
    this.errorType = SearchErrorType.none,
    this.message,
  });

  bool get hasResults => results.isNotEmpty;
  bool get isSuccess => errorType == SearchErrorType.none;

  factory SearchOutcome.success(List<T> results) =>
      SearchOutcome(results: results);

  factory SearchOutcome.failure(SearchErrorType errorType, {String? message}) =>
      SearchOutcome(results: const [], errorType: errorType, message: message);
}

enum SearchErrorType {
  none,
  noResults,
  cancelled,
  notFound,
  rateLimited,
  network,
  parse,
  unknown,
}
