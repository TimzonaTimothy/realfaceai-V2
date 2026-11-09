// // class CreditDisplay {
// //   /// Base rate derived from Starter pack: 2000 coins = $20.00 -> 1 coin = $0.01

// //   /// Convert raw backend credits to human-readable time string.
// //   /// Time varies because each model has a different compute cost!
// //   static String toTime(double credits, {String modelType = 'realtime'}) {
// //     double seconds;

// //     switch (modelType) {
// //       case 'v2v':
// //         // Cost: $0.04/sec -> 2.66 credits/sec -> 1 credit = 0.375 seconds
// //         seconds = credits * 0.375;
// //         break;
// //       case 'lipsync':
// //         // Cost: $0.01/sec -> 0.66 credits/sec -> 1 credit = 1.5 seconds
// //         seconds = credits * 1.5;
// //         break;
// //       case 'image':
// //         // Cost: $0.02/image -> 1.33 credits/image
// //         final images = (credits / 1.333).floor();
// //         return '$images images';
// //       case 'realtime':
// //       default:
// //         // Cost: $0.02/sec -> 2.0 credits/sec -> 1 credit = 0.50 seconds
// //         // (This means 1000 credits -> 500s -> 8m 20s)
// //         seconds = credits * 0.50;
// //         break;
// //     }

// //     final totalSeconds = seconds.floor();
// //     if (totalSeconds < 60) return '${totalSeconds}s';

// //     final mins = totalSeconds ~/ 60;
// //     final secs = totalSeconds % 60;
// //     return '${mins}m ${secs.toString().padLeft(2, '0')}s';
// //   }

// //   /// Show the estimated base monetary value (1 credit = $0.01)
// //   static String toMoney(double credits) {
// //     return '\$${(credits * 0.01).toStringAsFixed(2)}';
// //   }
// // }

// class CreditDisplay {
//   /// Base rate derived from Starter pack: 2000 coins = $20.00 -> 1 coin = $0.01

//   /// Convert raw backend credits to human-readable time string.
//   /// Time varies because each model has a different compute cost!
//   static String toTime(double credits, {String modelType = 'realtime'}) {
//     double seconds;

//     switch (modelType) {
//       case 'v2v':
//         // Cost: $0.04/sec -> 2.66 credits/sec -> 1 credit = 0.375 seconds
//         seconds = credits * 0.375;
//         break;
//       case 'lipsync':
//         // Cost: $0.01/sec -> 0.66 credits/sec -> 1 credit = 1.5 seconds
//         seconds = credits * 1.5;
//         break;
//       case 'image':
//         // Cost: $0.02/image -> 1.33 credits/image
//         final images = (credits / 1.333).floor();
//         return '$images images';
//       case 'realtime':
//       default:
//         // Cost: $0.02/sec -> 2.0 credits/sec -> 1 credit = 0.50 seconds
//         // (This means 1000 credits -> 500s -> 8m 20s)
//         seconds = credits * 0.50;
//         break;
//     }

//     final totalSeconds = seconds.floor();
//     if (totalSeconds < 60) return '${totalSeconds}s';

//     final mins = totalSeconds ~/ 60;
//     final secs = totalSeconds % 60;
//     return '${mins}m ${secs.toString().padLeft(2, '0')}s';
//   }

//   /// Show the estimated base monetary value (1 credit = $0.01)
//   static String toMoney(double credits) {
//     return '\$${(credits * 0.01).toStringAsFixed(2)}';
//   }
// }

class CreditDisplay {
  /// Base rate derived from Starter pack: 2000 coins = $20.00 -> 1 coin = $0.01

  /// Convert raw backend credits to streaming time left.
  /// Streaming costs 2 credits/sec ($0.02/sec), so 1 credit = 0.5 seconds
  /// (1000 credits -> 500 s -> 8m 20s).
  static String toTime(double credits) {
    final seconds = credits * 0.50;

    final totalSeconds = seconds.floor();
    if (totalSeconds < 60) return '${totalSeconds}s';

    final mins = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${mins}m ${secs.toString().padLeft(2, '0')}s';
  }

  /// Show the estimated base monetary value (1 credit = $0.01)
  static String toMoney(double credits) {
    return '\$${(credits * 0.01).toStringAsFixed(2)}';
  }
}