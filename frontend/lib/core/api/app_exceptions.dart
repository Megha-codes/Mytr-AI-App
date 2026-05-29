sealed class AppException implements Exception {
  final String message;
  final int? statusCode;

  AppException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class UnauthorisedException extends AppException {
  UnauthorisedException([super.message = 'Session expired. Please login again.', super.statusCode = 401]);
}

class NotFoundException extends AppException {
  NotFoundException([super.message = 'Requested data not found.', super.statusCode = 404]);
}

class NetworkException extends AppException {
  NetworkException([super.message = 'No internet connection. Please check your network.', super.statusCode]);
}

class ServerException extends AppException {
  ServerException([super.message = 'Something went wrong on our end. Try again later.', super.statusCode = 500]);
}

class ValidationException extends AppException {
  final Map<String, dynamic>? errors;
  ValidationException({String message = 'Invalid data provided.', int? statusCode = 422, this.errors})
      : super(message, statusCode);
}

class RateLimitException extends AppException {
  final int? retryAfterSeconds;
  RateLimitException({String message = 'Too many requests. Slow down.', int? statusCode = 429, this.retryAfterSeconds})
      : super(message, statusCode);
}

class UnknownException extends AppException {
  UnknownException([super.message = 'An unexpected error occurred.', super.statusCode]);
}
