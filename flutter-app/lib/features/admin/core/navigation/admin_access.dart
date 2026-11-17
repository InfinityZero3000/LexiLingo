import '../permissions/admin_permissions.dart';
import 'admin_nav.dart';

/// Whether this admin may open [location]. Permissions that have not loaded
/// yet do not block: the backend still refuses, and the screen then shows the
/// 403 state.
bool adminMayOpen(
  String location, {
  required bool isSuperAdmin,
  required AdminPermissions permissions,
}) {
  final item = adminNavItemFor(location);
  if (item == null) return true;
  if (item.superOnly) return isSuperAdmin;
  final required = item.permission;
  if (required == null || !permissions.isReady) return true;
  return permissions.can(required);
}
