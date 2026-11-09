// // class ErrorHandler {
// //   /// Sanitizes an error message to prevent leaking domain names or internal networking issues to the user.
// //   static String sanitize(dynamic error) {
// //     if (error == null) return 'An unknown error occurred.';
// //     final str = error.toString();

// //     // Check for common network-related exceptions that bubble up
// //     if (str.contains('SocketException') ||
// //         str.contains('Failed host lookup') ||
// //         str.contains('Connection refused') ||
// //         str.contains('HandshakeException') ||
// //         str.contains('ClientException')) {
// //       return 'Connection error. Please check your internet connection.';
// //     }

// //     // Fallback unhandled error
// //     return 'Error: $str';
// //   }
// // }

// class ErrorHandler {
//   /// Sanitizes an error message to prevent leaking domain names or internal networking issues to the user.
//   static String sanitize(dynamic error) {
//     if (error == null) return 'An unknown error occurred.';
//     final str = error.toString();

//     // Check for common network-related exceptions that bubble up
//     if (str.contains('SocketException') ||
//         str.contains('Failed host lookup') ||
//         str.contains('Connection refused') ||
//         str.contains('HandshakeException') ||
//         str.contains('ClientException')) {
//       return 'Connection error. Please check your internet connection.';
//     }

//     // Fallback unhandled error
//     return 'Error: $str';
//   }
// }

class ErrorHandler {
  /// Sanitizes an error message to prevent leaking domain names or internal networking issues to the user.
  static String sanitize(dynamic error) {
    if (error == null) return 'An unknown error occurred.';
    final str = error.toString();

    // Check for common network-related exceptions that bubble up
    if (str.contains('SocketException') ||
        str.contains('Failed host lookup') ||
        str.contains('Connection refused') ||
        str.contains('HandshakeException') ||
        str.contains('ClientException')) {
      return 'Connection error. Please check your internet connection.';
    }

    // Fallback unhandled error
    return 'Error: $str';
  }
}
