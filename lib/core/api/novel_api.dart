import 'package:dio/dio.dart';

class NovelApi {
  final Dio _dio;
  NovelApi(this._dio);

  Future<List<Map<String, dynamic>>> getNovels({
    int page = 1,
    int perPage = 20,
    String orderby = 'modified',
    String order = 'desc',
    int? genreId,
    List<int>? genreIds,   // multi-select genres từ filter
    List<int>? teamIds,    // multi-select nhóm dịch từ filter
    List<int>? include,    // fetch specific post IDs (dùng cho ranking two-step)
    String? search,
    String? authorName,
    int? teamId,
    String? status,
  }) async {
    // views/rating → sort bằng meta_value_num
    final String actualOrderby;
    final String? metaKey;
    switch (orderby) {
      case 'views':          // all-time views
        actualOrderby = 'meta_value_num';
        metaKey = '_init_view_count';
        break;
      case 'views_week':    // top tuần
        actualOrderby = 'meta_value_num';
        metaKey = '_init_view_week_count';
        break;
      case 'views_month':   // top tháng
        actualOrderby = 'meta_value_num';
        metaKey = '_init_view_month_count';
        break;
      case 'rating':
        actualOrderby = 'meta_value_num';
        metaKey = '_app_rating_avg';
        break;
      default:
        actualOrderby = orderby;
        metaKey = null;
    }

    // Gộp genreIds + genreId (backward compat)
    final effectiveGenres = genreIds ?? (genreId != null ? [genreId] : null);

    final params = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      'orderby': actualOrderby,
      'order': order,
      '_embed': 'wp:featuredmedia,author,wp:term',
      if (metaKey != null) 'meta_key': metaKey,
      if (effectiveGenres != null && effectiveGenres.isNotEmpty)
        'genre': effectiveGenres.length == 1
            ? effectiveGenres.first
            : effectiveGenres,
      if (search != null && search.isNotEmpty) 'search': search,
      if (authorName != null && authorName.isNotEmpty) 'author_name': authorName,
      if (teamIds != null && teamIds.isNotEmpty)
        'team': teamIds.length == 1 ? teamIds.first : teamIds,
      if (teamId != null && (teamIds == null || teamIds.isEmpty)) 'team': teamId,
      if (status != null) 'manga_status': status,
      // Khi dùng include, bỏ page/orderby để WP trả đúng thứ tự IDs
      if (include != null && include.isNotEmpty) 'include': include,
    };
    final res = await _dio.get('/wp/v2/manga', queryParameters: params);
    return List<Map<String, dynamic>>.from(res.data);
  }

  Future<Map<String, dynamic>> getNovelById(int id) async {
    final res = await _dio.get(
      '/wp/v2/manga/$id',
      queryParameters: {'_embed': 'wp:featuredmedia,author,wp:term'},
    );
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getChapters({
    required int novelId,
    int page = 1,
    int perPage = 50,
  }) async {
    final res = await _dio.get('/initmanga/v1/chapters', queryParameters: {
      'manga_id': novelId,
      'paged': page,
      'per_page': perPage,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<int> getChapterCount(int novelId) async {
    final res = await _dio.get('/initmanga/v1/chapters', queryParameters: {
      'manga_id': novelId,
      'paged': 1,
      'per_page': 1,
    });
    return (res.data['total_pages'] as int?) ?? 0;
  }

  Future<Map<String, dynamic>> getChapterById(int id) async {
    final res = await _dio.get('/initmanga/v1/chapter/$id');
    return Map<String, dynamic>.from(res.data);
  }

  Future<List<Map<String, dynamic>>> getGenres({int perPage = 100}) async {
    final res = await _dio.get('/wp/v2/genre', queryParameters: {'per_page': perPage});
    return List<Map<String, dynamic>>.from(res.data);
  }

  Future<List<Map<String, dynamic>>> getTeams({int perPage = 100}) async {
    final res = await _dio.get('/wp/v2/team', queryParameters: {'per_page': perPage});
    return List<Map<String, dynamic>>.from(res.data);
  }

  Future<List<Map<String, dynamic>>> getNovelsByAuthorTax(
      int authorTermId, {int perPage = 10}) async {
    final res = await _dio.get('/wp/v2/manga', queryParameters: {
      'author_tax': authorTermId,
      'per_page': perPage,
      '_embed': 'wp:featuredmedia,author,wp:term',
    });
    return List<Map<String, dynamic>>.from(res.data);
  }

  Future<List<Map<String, dynamic>>> getRanking({
    String tab = 'views',
    String? range = 'week', // 'week' | 'month' | null (all-time)
    int limit = 20,
  }) async {
    final res = await _dio.get('/initmanga/v1/ranking', queryParameters: {
      'tab': tab,
      if (range != null) 'range': range,
      'limit': limit,
    });
    final data = res.data;
    // Support both {items: [...]} and direct array formats
    if (data is List) {
      return List<Map<String, dynamic>>.from(data);
    }
    if (data is Map && data['items'] != null) {
      return List<Map<String, dynamic>>.from(data['items'] as List);
    }
    if (data is Map && data['data'] != null) {
      return List<Map<String, dynamic>>.from(data['data'] as List);
    }
    return [];
  }

  // ── Reviews (app_review comment type) ──────────────────────────────
  Future<Map<String, dynamic>> getReviews(int mangaId, {int page = 1}) async {
    final res = await _dio.get('/initmanga/v1/reviews', queryParameters: {
      'manga_id': mangaId,
      'page': page,
      'per_page': 20,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> submitReview(int mangaId, String content, {required int rating}) async {
    await _dio.post('/initmanga/v1/reviews', data: {
      'manga_id': mangaId,
      'content': content,
      'rating': rating,
    });
  }

  // ── Comments (WP standard) ──────────────────────────────────────────
  Future<Map<String, dynamic>> getComments(int postId, {int page = 1}) async {
    final res = await _dio.get('/wp/v2/comments', queryParameters: {
      'post': postId,
      'per_page': 20,
      'page': page,
      'order': 'desc',
      'type': 'comment',
      'parent': 0,
    });
    final total = int.tryParse(res.headers.value('x-wp-total') ?? '0') ?? 0;
    final totalPages = int.tryParse(res.headers.value('x-wp-totalpages') ?? '1') ?? 1;
    return {
      'items': List<Map<String, dynamic>>.from(res.data as List),
      'total': total,
      'total_pages': totalPages,
    };
  }

  Future<void> submitComment(int postId, String content, {int? parentId}) async {
    await _dio.post('/wp/v2/comments', data: {
      'post': postId,
      'content': content,
      if (parentId != null && parentId > 0) 'parent': parentId,
    });
  }

  Future<List<Map<String, dynamic>>> getCommentReplies(
      int postId, int parentId) async {
    final res = await _dio.get('/wp/v2/comments', queryParameters: {
      'post': postId,
      'parent': parentId,
      'per_page': 50,
      'order': 'asc',
    });
    return List<Map<String, dynamic>>.from(res.data as List);
  }
}

class UserApi {
  final Dio _dio;
  UserApi(this._dio);

  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await _dio.post('/jwt-auth/v1/token', data: {
      'username': username,
      'password': password,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> register(
      String username, String email, String password) async {
    final res = await _dio.post('/initmanga/v1/register', data: {
      'username': username,
      'email': email,
      'password': password,
    });
    return Map<String, dynamic>.from(res.data);
  }

  Future<Map<String, dynamic>> getMe() async {
    final res = await _dio.get('/wp/v2/users/me',
        queryParameters: {'context': 'edit'});
    return Map<String, dynamic>.from(res.data);
  }

  Future<void> deleteAccount() async {
    await _dio.delete('/initmanga/v1/account');
  }

  Future<void> trackReading(int mangaId, int chapterId) async {
    await _dio.post('/initmanga/v1/track-reading', data: {
      'manga_id': mangaId,
      'chapter_id': chapterId,
    });
  }
}
