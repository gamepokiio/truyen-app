/// Genre IDs bị loại trừ khỏi filter và danh sách truyện
const kExcludedGenreIds = {25, 27, 64, 45};

/// Lọc truyện áp dụng TOÀN APP:
/// • Loại orphan (không có genre nào)
/// • Loại truyện chỉ thuộc các genre bị loại trừ
List<Novel> filterNovels(List<Novel> novels) => novels
    .where((n) => n.genres.any((g) => !kExcludedGenreIds.contains(g.id)))
    .toList();

class NovelTerm {
  final int id;
  final String name;
  const NovelTerm({required this.id, required this.name});
}

class Novel {
  final int id;
  final String title;
  final String slug;
  final String? excerpt;
  final String? description;
  final String? coverUrl;
  final String? authorName;
  final int? authorTermId;
  final List<NovelTerm> genres;
  final List<NovelTerm> groups;
  final String status;
  final int viewCount;
  final double rating;
  final double appRatingAvg;
  final int appReviewCount;
  final int chapterCount;
  final String? latestChapterTitle;
  final DateTime? updatedAt;

  const Novel({
    required this.id,
    required this.title,
    required this.slug,
    this.excerpt,
    this.description,
    this.coverUrl,
    this.authorName,
    this.authorTermId,
    this.genres = const <NovelTerm>[],
    this.groups = const <NovelTerm>[],
    this.status = 'ongoing',
    this.viewCount = 0,
    this.rating = 0,
    this.appRatingAvg = 0,
    this.appReviewCount = 0,
    this.chapterCount = 0,
    this.latestChapterTitle,
    this.updatedAt,
  });

  factory Novel.fromJson(Map<String, dynamic> json) {
    return Novel(
      id: _toInt(json['id']),
      title: _stripHtml(_rendered(json['title'])),
      slug: json['slug'] ?? '',
      excerpt: _stripHtml(_rendered(json['excerpt'])),
      description: json['content'] is Map && json['content']['rendered'] != null
          ? _stripHtml(json['content']['rendered'] as String)
          : (json['content'] is String ? _stripHtml(json['content'] as String) : null),
      coverUrl: json['_embedded']?['wp:featuredmedia']?[0]?['source_url'] ??
          json['featured_image_url'] ??
          json['cover'] ??         // ranking endpoint
          json['thumbnail'],       // fallback
      authorName: _parseFirstTerm(json['_embedded']?['wp:term'], 'author_tax')
          ?? json['_embedded']?['author']?[0]?['name']?.toString()
          ?? (json['author'] is String ? json['author'] as String : null),
      authorTermId: _parseFirstTermId(json['_embedded']?['wp:term'], 'author_tax'),
      genres: _parseTermsWithId(json['_embedded']?['wp:term'], 'genre'),
      groups: _parseTermsWithId(json['_embedded']?['wp:term'], 'team'),
      status: json['manga_status'] ?? json['meta']?['_manga_status'] ?? 'ongoing',
      viewCount: _toInt(json['meta']?['_manga_views'] ?? json['views'] ?? json['view_count']),
      rating: _toDouble(json['meta']?['_manga_rating']),
      appRatingAvg: (json['app_rating']?['avg'] as num?)?.toDouble() ?? 0.0,
      appReviewCount: (json['app_rating']?['count'] as num?)?.toInt() ?? 0,
      chapterCount: _toInt(json['meta']?['_manga_chapter_count'] ?? json['chapter_count']),
      latestChapterTitle: json['meta']?['_latest_chapter_title'],
      updatedAt: json['modified'] != null
          ? DateTime.tryParse(json['modified'])
          : null,
    );
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  /// Returns rendered string from either WP REST `{rendered: "..."}` or plain string.
  static String _rendered(dynamic v) {
    if (v == null) return '';
    if (v is Map) return (v['rendered'] as String?) ?? '';
    return v.toString();
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .trim();
  }

  static String? _parseFirstTerm(dynamic embedded, String taxonomy) {
    if (embedded == null) return null;
    for (final termGroup in embedded as List) {
      if (termGroup is List && termGroup.isNotEmpty) {
        final first = termGroup.first;
        if (first is Map && first['taxonomy'] == taxonomy) {
          return first['name']?.toString();
        }
      }
    }
    return null;
  }

  static int? _parseFirstTermId(dynamic embedded, String taxonomy) {
    if (embedded == null) return null;
    for (final termGroup in embedded as List) {
      if (termGroup is List && termGroup.isNotEmpty) {
        final first = termGroup.first;
        if (first is Map && first['taxonomy'] == taxonomy) {
          return first['id'] as int?;
        }
      }
    }
    return null;
  }

  static List<NovelTerm> _parseTermsWithId(dynamic embedded, String taxonomy) {
    if (embedded == null) return [];
    for (final termGroup in embedded as List) {
      if (termGroup is List && termGroup.isNotEmpty) {
        final first = termGroup.first;
        if (first is Map && first['taxonomy'] == taxonomy) {
          return termGroup
              .where((t) => t['name']?.toString().isNotEmpty == true)
              .map((t) => NovelTerm(
                    id: t['id'] as int? ?? 0,
                    name: t['name']?.toString() ?? '',
                  ))
              .toList();
        }
      }
    }
    return [];
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'Hoàn thành';
      case 'source_hiatus':
        return 'Tạm dừng';
      case 'dropped':
        return 'Bị hủy';
      case 'season_end':
        return 'Kết thúc mùa';
      case 'caught_up':
        return 'Đã theo kịp';
      default:
        return 'Đang ra';
    }
  }
}

class Chapter {
  final int id;
  final int novelId;
  final String title;
  final String slug;
  final int chapterNumber;
  final String? content;
  final DateTime? publishedAt;
  final bool isRead;

  const Chapter({
    required this.id,
    required this.novelId,
    required this.title,
    required this.slug,
    required this.chapterNumber,
    this.content,
    this.publishedAt,
    this.isRead = false,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] as int,
      novelId: json['manga_id'] ?? json['parent'] ?? 0,
      title: json['title'] ?? _stripHtml(json['title']?['rendered'] ?? ''),
      slug: json['slug'] ?? '',
      chapterNumber: (json['number'] ?? json['chapter_index'] ?? 0).toInt(),
      content: json['content'],
      publishedAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'])
          : json['date'] != null
              ? DateTime.tryParse(json['date'])
              : null,
      isRead: json['is_read'] ?? false,
    );
  }

  static String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
}

class UserProfile {
  final int id;
  final String username;
  final String displayName;
  final String? email;
  final String? avatarUrl;
  final DateTime? registeredDate;
  final int level;

  const UserProfile({
    required this.id,
    required this.username,
    required this.displayName,
    this.email,
    this.avatarUrl,
    this.registeredDate,
    this.level = 1,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as int,
      username: json['user_login'] ?? json['slug'] ?? '',
      displayName: json['name'] ?? json['display_name'] ?? '',
      email: json['email'],
      avatarUrl: json['avatar_urls']?['96'],
      registeredDate: json['registered_date'] != null
          ? DateTime.tryParse(json['registered_date'])
          : null,
      level: (json['iue_level'] as int?) ?? 1,
    );
  }

  String get rankName {
    if (level >= 100) return 'Thánh Nhân';
    if (level >= 50) return 'Tông Sư';
    if (level >= 25) return 'Cao Thủ';
    if (level >= 10) return 'Học Đồ';
    return 'Tân Binh';
  }
}

class NovelComment {
  final int id;
  final String authorName;
  final String? authorAvatarUrl;
  final int authorLevel;
  final String content;
  final DateTime? date;
  final int replyCount;
  final int parentId;
  final int rating;

  const NovelComment({
    required this.id,
    required this.authorName,
    this.authorAvatarUrl,
    this.authorLevel = 0,
    required this.content,
    this.date,
    this.replyCount = 0,
    this.parentId = 0,
    this.rating = 0,
  });

  String get rankName {
    if (authorLevel >= 100) return 'Thánh Nhân';
    if (authorLevel >= 50) return 'Tông Sư';
    if (authorLevel >= 25) return 'Cao Thủ';
    if (authorLevel >= 10) return 'Học Đồ';
    return '';
  }

  static const Map<String, int> _rankColors = {
    'Thánh Nhân': 0xFF1565C0,
    'Tông Sư': 0xFF6A1B9A,
    'Cao Thủ': 0xFF546E7A,
    'Học Đồ': 0xFFE65100,
  };

  int? get rankColor => rankName.isEmpty ? null : _rankColors[rankName];

  factory NovelComment.fromJson(Map<String, dynamic> json) {
    final avatarUrls = json['author_avatar_urls'];
    String? avatar = json['author_avatar'] as String?;
    if (avatar == null && avatarUrls is Map) {
      avatar = (avatarUrls['48'] ?? avatarUrls['96'] ??
          (avatarUrls.values.isNotEmpty ? avatarUrls.values.first : null))
          as String?;
    }
    final rawContent = json['content'] is Map
        ? (json['content']['rendered'] as String? ?? '')
        : (json['content'] as String? ?? '');
    return NovelComment(
      id: (json['id'] as num).toInt(),
      authorName: json['author_name'] as String? ?? 'Ẩn danh',
      authorAvatarUrl: avatar,
      authorLevel: (json['author_level'] as num?)?.toInt() ?? 0,
      content: rawContent.replaceAll(RegExp(r'<[^>]*>'), '').trim(),
      date: json['date'] != null ? DateTime.tryParse(json['date'] as String) : null,
      replyCount: (json['reply_count'] as num?)?.toInt() ?? 0,
      parentId: (json['parent'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReadingProgress {
  final int novelId;
  final int chapterId;
  final int paragraphIndex;
  final DateTime updatedAt;

  const ReadingProgress({
    required this.novelId,
    required this.chapterId,
    required this.paragraphIndex,
    required this.updatedAt,
  });
}
