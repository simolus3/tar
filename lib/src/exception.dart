import 'package:meta/meta.dart';

/// An exception indicating that there was an issue parsing a `.tar` file.
/// Intended ot be seen by the user.
class TarException extends FormatException {
  @internal
  TarException(String message) : super(message);

  @internal
  factory TarException.header(String message) {
    return TarException('Invalid header: $message');
  }
}
