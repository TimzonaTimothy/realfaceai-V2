import '../models/maintenance_info.dart';

class MaintenanceException implements Exception {
  final MaintenanceInfo info;
  const MaintenanceException(this.info);

  @override
  String toString() => 'MaintenanceException: ${info.message}';
}
