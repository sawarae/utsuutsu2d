/// Allowed users for puppet
enum AllowedUsers {
  onlyAuthor,
  onlyLicensee,
  everyone,
}

/// Allowed redistribution
enum AllowedRedistribution {
  prohibited,
  viralLicense,
  copyleft,
}

/// Allowed modification
enum AllowedModification {
  prohibited,
  personalUseOnly,
  allowRedistribution,
}

/// Usage rights configuration
class PuppetUsageRights {
  AllowedUsers allowedUsers;
  bool allowViolence;
  bool allowSexual;
  bool allowCommercial;
  AllowedRedistribution allowRedistribution;
  AllowedModification allowModification;
  bool requireAttribution;

  PuppetUsageRights({
    this.allowedUsers = AllowedUsers.everyone,
    this.allowViolence = false,
    this.allowSexual = false,
    this.allowCommercial = false,
    this.allowRedistribution = AllowedRedistribution.prohibited,
    this.allowModification = AllowedModification.prohibited,
    this.requireAttribution = false,
  });

  factory PuppetUsageRights.fromJson(Map<String, dynamic> json) {
    return PuppetUsageRights(
      allowedUsers: _parseAllowedUsers(json['allowed_users']),
      allowViolence: json['allow_violence'] ?? false,
      allowSexual: json['allow_sexual'] ?? false,
      allowCommercial: json['allow_commercial'] ?? false,
      allowRedistribution: _parseAllowedRedistribution(json['allow_redistribution']),
      allowModification: _parseAllowedModification(json['allow_modification']),
      requireAttribution: json['require_attribution'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'allowed_users': _allowedUsersToString(allowedUsers),
      'allow_violence': allowViolence,
      'allow_sexual': allowSexual,
      'allow_commercial': allowCommercial,
      'allow_redistribution': _allowedRedistributionToString(allowRedistribution),
      'allow_modification': _allowedModificationToString(allowModification),
      'require_attribution': requireAttribution,
    };
  }

  static String _allowedUsersToString(AllowedUsers value) {
    switch (value) {
      case AllowedUsers.onlyAuthor:
        return 'only_author';
      case AllowedUsers.onlyLicensee:
        return 'only_licensee';
      case AllowedUsers.everyone:
        return 'everyone';
    }
  }

  static String _allowedRedistributionToString(AllowedRedistribution value) {
    switch (value) {
      case AllowedRedistribution.prohibited:
        return 'prohibited';
      case AllowedRedistribution.viralLicense:
        return 'viral_license';
      case AllowedRedistribution.copyleft:
        return 'copyleft';
    }
  }

  static String _allowedModificationToString(AllowedModification value) {
    switch (value) {
      case AllowedModification.prohibited:
        return 'prohibited';
      case AllowedModification.personalUseOnly:
        return 'personal_use_only';
      case AllowedModification.allowRedistribution:
        return 'allow_redistribution';
    }
  }

  static AllowedUsers _parseAllowedUsers(dynamic value) {
    if (value == null) return AllowedUsers.everyone;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'only_author':
          return AllowedUsers.onlyAuthor;
        case 'only_licensee':
          return AllowedUsers.onlyLicensee;
        default:
          return AllowedUsers.everyone;
      }
    }
    return AllowedUsers.everyone;
  }

  static AllowedRedistribution _parseAllowedRedistribution(dynamic value) {
    if (value == null) return AllowedRedistribution.prohibited;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'viral_license':
          return AllowedRedistribution.viralLicense;
        case 'copyleft':
          return AllowedRedistribution.copyleft;
        default:
          return AllowedRedistribution.prohibited;
      }
    }
    return AllowedRedistribution.prohibited;
  }

  static AllowedModification _parseAllowedModification(dynamic value) {
    if (value == null) return AllowedModification.prohibited;
    if (value is String) {
      switch (value.toLowerCase()) {
        case 'personal_use_only':
          return AllowedModification.personalUseOnly;
        case 'allow_redistribution':
          return AllowedModification.allowRedistribution;
        default:
          return AllowedModification.prohibited;
      }
    }
    return AllowedModification.prohibited;
  }
}

/// Puppet metadata
class PuppetMeta {
  String name;
  String version;
  String? rigger;
  String? artist;
  String? copyright;
  String? licenseUrl;
  String? contact;
  String? reference;
  int? thumbnailId;
  bool preservePixels;
  PuppetUsageRights rights;

  PuppetMeta({
    this.name = '',
    this.version = '1.0',
    this.rigger,
    this.artist,
    this.copyright,
    this.licenseUrl,
    this.contact,
    this.reference,
    this.thumbnailId,
    this.preservePixels = false,
    PuppetUsageRights? rights,
  }) : rights = rights ?? PuppetUsageRights();

  factory PuppetMeta.fromJson(Map<String, dynamic> json) {
    return PuppetMeta(
      name: json['name'] ?? '',
      version: json['version'] ?? '1.0',
      rigger: json['rigger'],
      artist: json['artist'],
      copyright: json['copyright'],
      licenseUrl: json['license_url'],
      contact: json['contact'],
      reference: json['reference'],
      thumbnailId: json['thumbnail_id'],
      preservePixels: json['preserve_pixels'] ?? false,
      rights: json['rights'] != null
          ? PuppetUsageRights.fromJson(json['rights'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'version': version,
      'rigger': rigger,
      'artist': artist,
      'copyright': copyright,
      'license_url': licenseUrl,
      'contact': contact,
      'reference': reference,
      'thumbnail_id': thumbnailId,
      'preserve_pixels': preservePixels,
      'rights': rights.toJson(),
    };
  }

  @override
  String toString() => 'PuppetMeta(name: $name, version: $version)';
}
