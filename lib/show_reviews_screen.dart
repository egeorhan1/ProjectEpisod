import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'review_detail_screen.dart';
import 'theme/app_colors.dart';

class ShowReviewsScreen extends StatefulWidget {
  final int showId;
  final String showName;
  final String? posterPath;

  const ShowReviewsScreen({
    super.key,
    required this.showId,
    required this.showName,
    this.posterPath,
  });

  @override
  State<ShowReviewsScreen> createState() => _ShowReviewsScreenState();
}

class _ShowReviewsScreenState extends State<ShowReviewsScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late TabController _tabController;
  String _sortBy = 'newest'; // 'newest' veya 'likes'
  List allReviews = [];
  List friendReviews = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchReviews();
  }

  Future<void> _fetchReviews() async {
    setState(() => isLoading = true);
    final myId = _supabase.auth.currentUser?.id;

    try {
      // 1. Tüm incelemeleri çek (Beğeni sayılarıyla birlikte)
      final res = await _supabase
          .from('comments')
          .select('*, profiles(id, username), comment_likes(count)')
          .eq('show_id', widget.showId)
          .not('rating', 'is', null); // Sadece puanlı olanlar reviewdur

      List reviews = res as List;

      // Sıralama mantığı
      if (_sortBy == 'newest') {
        reviews.sort(
          (a, b) => DateTime.parse(
            b['created_at'],
          ).compareTo(DateTime.parse(a['created_at'])),
        );
      } else {
        reviews.sort((a, b) {
          int countA =
              a['comment_likes'] != null && a['comment_likes'].isNotEmpty
              ? a['comment_likes'][0]['count']
              : 0;
          int countB =
              b['comment_likes'] != null && b['comment_likes'].isNotEmpty
              ? b['comment_likes'][0]['count']
              : 0;
          return countB.compareTo(countA);
        });
      }

      // 2. Friends sekmesi için takip ettiklerimi filtrele
      List fReviews = [];
      if (myId != null) {
        final followingRes = await _supabase
            .from('follows')
            .select('following_id')
            .eq('follower_id', myId);
        final followingIds = (followingRes as List)
            .map((f) => f['following_id'])
            .toList();
        fReviews = reviews
            .where((r) => followingIds.contains(r['user_id']))
            .toList();
      }

      if (mounted) {
        setState(() {
          allReviews = reviews;
          friendReviews = fReviews;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Review fetch error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            const Text(
              "Reviews of",
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            Text(
              widget.showName,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          // SIRALAMA BUTONU
          IconButton(
            icon: Icon(
              Icons.sort,
              color: _sortBy == 'likes'
                  ? AppColors.accent
                  : AppColors.textPrimary,
            ),
            onPressed: _showSortMenu,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.textPrimary,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: AppColors.divider,
          tabs: const [
            Tab(text: "Everyone"),
            Tab(text: "Friends"),
          ],
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildReviewList(allReviews),
                _buildReviewList(friendReviews),
              ],
            ),
    );
  }

  void _showSortMenu() {
    showModalBottomSheet(
      backgroundColor: AppColors.surface,
      context: context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(
              Icons.access_time,
              color: AppColors.textPrimary,
            ),
            title: const Text(
              "Newest First",
              style: TextStyle(color: AppColors.textPrimary),
            ),
            onTap: () {
              setState(() => _sortBy = 'newest');
              Navigator.pop(context);
              _fetchReviews();
            },
          ),
          ListTile(
            leading: const Icon(Icons.favorite, color: AppColors.textPrimary),
            title: const Text(
              "Most Liked",
              style: TextStyle(color: AppColors.textPrimary),
            ),
            onTap: () {
              setState(() => _sortBy = 'likes');
              Navigator.pop(context);
              _fetchReviews();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReviewList(List reviews) {
    if (reviews.isEmpty)
      return const Center(
        child: Text(
          "No reviews yet.",
          style: TextStyle(color: AppColors.textMuted),
        ),
      );
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: reviews.length,
      separatorBuilder: (c, i) =>
          const Divider(color: AppColors.divider, height: 32),
      itemBuilder: (context, index) {
        final r = reviews[index];
        return _buildReviewItem(r);
      },
    );
  }

  Widget _buildReviewItem(Map r) {
    final double rating = (r['rating'] as num).toDouble();
    final int likes =
        r['comment_likes'] != null && r['comment_likes'].isNotEmpty
        ? r['comment_likes'][0]['count']
        : 0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (c) => ReviewDetailScreen(
            review: r,
            showName: widget.showName,
            posterPath: widget.posterPath,
          ),
        ),
      ).then((_) => _fetchReviews()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Yıldızlar (Letterboxd stili yeşil)
              Row(
                children: List.generate(5, (i) {
                  double val = rating / 2;
                  if (val >= i + 1)
                    return const Icon(
                      Icons.star,
                      color: AppColors.accent,
                      size: 14,
                    );
                  if (val >= i + 0.5)
                    return const Icon(
                      Icons.star_half,
                      color: AppColors.accent,
                      size: 14,
                    );
                  return const Icon(
                    Icons.star_border,
                    color: AppColors.textMuted,
                    size: 14,
                  );
                }),
              ),
              if (likes > 0) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.favorite,
                  color: AppColors.accentSecondary,
                  size: 12,
                ),
              ],
              const Spacer(),
              Text(
                r['profiles']['username'],
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 10,
                backgroundColor: AppColors.divider,
                child: Text(
                  r['profiles']['username'][0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 8,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            r['content'],
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
