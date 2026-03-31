import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_colors.dart';
import 'widgets/episod_user_avatar.dart';

class ForumScreen extends StatefulWidget {
  final int showId;
  final String showName;
  final int? seasonNumber; // Doluysa Bölüm forumudur, boşsa Dizi forumudur
  final int? episodeNumber;

  const ForumScreen({
    super.key,
    required this.showId,
    required this.showName,
    this.seasonNumber,
    this.episodeNumber,
  });

  @override
  State<ForumScreen> createState() => _ForumScreenState();
}

class _ForumScreenState extends State<ForumScreen> {
  final _supabase = Supabase.instance.client;
  final _commentController = TextEditingController();
  final _focusNode = FocusNode();

  List comments = [];
  List userLikes = [];
  Map? replyingTo;
  final Set<int> _expandedReplies = {};
  String _currentSort = 'Newest';

  // Hangi forumda olduğumuzu anlıyoruz
  bool get isEpisodeForum =>
      widget.seasonNumber != null && widget.episodeNumber != null;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final user = _supabase.auth.currentUser;

      // FORUM SİHRİ: Sadece 'rating' sütunu NULL olanları çekiyoruz (Yıldızlı incelemeler Reviews sayfasına gidecek)
      var query = _supabase
          .from('comments')
          .select('*, profiles(username), comment_likes(count)')
          .eq('show_id', widget.showId)
          .isFilter('rating', null);

      // Eğer bölüm forumundaysak bölüme göre filtrele, yoksa sadece diziye ait (sezonu null olan) yorumları getir
      if (isEpisodeForum) {
        query = query
            .eq('season_number', widget.seasonNumber!)
            .eq('episode_number', widget.episodeNumber!);
      } else {
        query = query.isFilter('season_number', null);
      }

      final results = await Future.wait<dynamic>([
        query,
        if (user != null)
          _supabase
              .from('comment_likes')
              .select('comment_id')
              .eq('user_id', user.id)
        else
          Future.value([]),
      ]);

      if (mounted) {
        setState(() {
          comments = results[0] as List;
          userLikes = (results[1] as List).map((l) => l['comment_id']).toList();
        });
      }
    } catch (e) {
      debugPrint("Forum error: $e");
    }
  }

  int _getLikes(Map c) =>
      c['comment_likes'] != null && c['comment_likes'].isNotEmpty
      ? (c['comment_likes'][0]['count'] ?? 0)
      : 0;
  int _getReplyCount(Map c) =>
      comments.where((r) => r['parent_id'] == c['id']).length;

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final user = _supabase.auth.currentUser;
    _commentController.clear();

    // Yanıt veriyorsak sekmesini otomatik aç
    if (replyingTo != null) _expandedReplies.add(replyingTo!['id']);

    await _supabase.from('comments').insert({
      'user_id': user!.id,
      'show_id': widget.showId,
      'season_number':
          widget.seasonNumber, // Null ise diziye, doluysa bölüme kaydeder
      'episode_number': widget.episodeNumber,
      'content': text,
      'parent_id': replyingTo?['id'],
    });

    setState(() => replyingTo = null);
    _focusNode.unfocus();
    _fetchData();
  }

  Future<void> _toggleLike(int commentId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    if (userLikes.contains(commentId)) {
      await _supabase
          .from('comment_likes')
          .delete()
          .eq('user_id', user.id)
          .eq('comment_id', commentId);
    } else {
      await _supabase.from('comment_likes').insert({
        'user_id': user.id,
        'comment_id': commentId,
      });
    }
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    // Sadece ana yorumları al ve sırala
    List mainComments = comments.where((c) => c['parent_id'] == null).toList();
    mainComments.sort((a, b) {
      if (_currentSort == 'Top Liked')
        return _getLikes(b).compareTo(_getLikes(a));
      if (_currentSort == 'Most Discussed')
        return _getReplyCount(b).compareTo(_getReplyCount(a));
      return DateTime.parse(
        b['created_at'],
      ).compareTo(DateTime.parse(a['created_at']));
    });

    // Başlığı duruma göre ayarla
    String title = isEpisodeForum
        ? "S${widget.seasonNumber} E${widget.episodeNumber} Forum"
        : "${widget.showName} Forum";

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.sort,
              color: AppColors.textPrimary,
              size: 22,
            ),
            color: AppColors.surfaceAlt,
            onSelected: (value) => setState(() => _currentSort = value),
            itemBuilder: (context) => [
              _buildPopupItem('Newest', Icons.access_time),
              _buildPopupItem('Top Liked', Icons.thumb_up_alt_outlined),
              _buildPopupItem('Most Discussed', Icons.forum_outlined),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchData,
              color: AppColors.accent,
              backgroundColor: AppColors.surface,
              child: mainComments.isEmpty
                  ? const Center(
                      child: Text(
                        "Be the first to start the discussion!",
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: mainComments.length,
                      itemBuilder: (context, i) {
                        final parent = mainComments[i];
                        final replies =
                            comments
                                .where((c) => c['parent_id'] == parent['id'])
                                .toList()
                              ..sort(
                                (a, b) => DateTime.parse(
                                  a['created_at'],
                                ).compareTo(DateTime.parse(b['created_at'])),
                              );
                        final bool isExpanded = _expandedReplies.contains(
                          parent['id'],
                        );

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ANA YORUM
                            _buildCommentTile(parent, isReply: false),

                            // YANITLARI GÖSTER/GİZLE BUTONU
                            if (replies.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 44,
                                  top: 4,
                                  bottom: 8,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      if (isExpanded)
                                        _expandedReplies.remove(parent['id']);
                                      else
                                        _expandedReplies.add(parent['id']);
                                    });
                                  },
                                  child: Row(
                                    children: [
                                      Icon(
                                        isExpanded
                                            ? Icons.keyboard_arrow_up
                                            : Icons.keyboard_arrow_down,
                                        color: AppColors.accent,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isExpanded
                                            ? "Hide replies"
                                            : "View ${replies.length} replies",
                                        style: const TextStyle(
                                          color: AppColors.accent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                            // YANITLAR
                            if (isExpanded)
                              ...replies.map(
                                (r) => Padding(
                                  padding: const EdgeInsets.only(
                                    left: 44,
                                    bottom: 8,
                                  ),
                                  child: _buildCommentTile(r, isReply: true),
                                ),
                              ),

                            const Divider(color: AppColors.divider, height: 32),
                          ],
                        );
                      },
                    ),
            ),
          ),

          // İŞTE YARIM KALAN O GÜZELİM MESAJ YAZMA KUTUSU BURASI
          _buildInputArea(),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, IconData icon) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(
            icon,
            color: _currentSort == value
                ? AppColors.accent
                : AppColors.textSecondary,
            size: 18,
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: _currentSort == value
                  ? AppColors.accent
                  : AppColors.textPrimary,
              fontSize: 14,
              fontWeight: _currentSort == value
                  ? FontWeight.bold
                  : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentTile(Map c, {required bool isReply}) {
    final bool isLiked = userLikes.contains(c['id']);
    final int likeCount = _getLikes(c);
    final Duration diff = DateTime.now().difference(
      DateTime.parse(c['created_at']).toLocal(),
    );
    String timeAgo = diff.inDays > 0
        ? "${diff.inDays}d"
        : diff.inHours > 0
        ? "${diff.inHours}h"
        : diff.inMinutes > 0
        ? "${diff.inMinutes}m"
        : "now";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          EpisodUserAvatar(
            username: c['profiles']['username'],
            radius: isReply ? 12 : 16,
            fontSize: 10,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      c['profiles']['username'],
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      timeAgo,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  c['content'],
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // BEĞEN BUTONU
                    GestureDetector(
                      onTap: () => _toggleLike(c['id']),
                      child: Row(
                        children: [
                          Icon(
                            isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                            size: 14,
                            color: isLiked
                                ? AppColors.accent
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            likeCount > 0 ? "$likeCount" : "",
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    // YANITLA BUTONU
                    if (!isReply)
                      GestureDetector(
                        onTap: () {
                          setState(() => replyingTo = c);
                          _focusNode.requestFocus();
                        },
                        child: const Text(
                          "Reply",
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // YARIM KALAN YER TAMAMLANDI: Mesaj giriş alanı
  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 10,
        left: 16,
        right: 16,
        top: 10,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: AppColors.divider,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // BİRİNE YANIT VERİYORSAK ÇIKAN BİLGİ ETİKETİ
          if (replyingTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                children: [
                  Text(
                    "Replying to ${replyingTo!['profiles']['username']}",
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => replyingTo = null),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),

          // MESAJ KUTUSU VE GÖNDER BUTONU
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  focusNode: _focusNode,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                  decoration: const InputDecoration(
                    hintText: "Add a comment...",
                    hintStyle: TextStyle(color: AppColors.textMuted),
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                onPressed: _postComment,
                icon: const Icon(Icons.send, color: AppColors.accent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
