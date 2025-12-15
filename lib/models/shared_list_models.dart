class SharedListInfo {
  final String shareId;
  final String listId;
  final String listName;
  final String ownerName;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int itemCount;
  final SharePermission permission;

  SharedListInfo({
    required this.shareId,
    required this.listId,
    required this.listName,
    required this.ownerName,
    required this.createdAt,
    required this.expiresAt,
    required this.itemCount,
    required this.permission,
  });

  factory SharedListInfo.fromJson(Map<String, dynamic> json) {
    return SharedListInfo(
      shareId: json['shareId'],
      listId: json['listId'],
      listName: json['listName'],
      ownerName: json['ownerName'] ?? 'Someone',
      createdAt: DateTime.parse(json['createdAt']),
      expiresAt: DateTime.parse(json['expiresAt']),
      itemCount: json['itemCount'] ?? 0,
      permission: SharePermission.values.firstWhere(
            (e) => e.toString() == 'SharePermission.${json['permission']}',
        orElse: () => SharePermission.view,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'shareId': shareId,
    'listId': listId,
    'listName': listName,
    'ownerName': ownerName,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'itemCount': itemCount,
    'permission': permission.name,
  };

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

enum SharePermission {
  view,      // Can only view the list
  edit,      // Can add/edit/remove items
  admin,     // Full control
}

extension SharePermissionExtension on SharePermission {
  String get displayName {
    switch (this) {
      case SharePermission.view:
        return 'View Only';
      case SharePermission.edit:
        return 'Can Edit';
      case SharePermission.admin:
        return 'Admin';
    }
  }

  String get description {
    switch (this) {
      case SharePermission.view:
        return 'Can view items but not make changes';
      case SharePermission.edit:
        return 'Can add, edit, and check off items';
      case SharePermission.admin:
        return 'Full control including deleting list';
    }
  }
}