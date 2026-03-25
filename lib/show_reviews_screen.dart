import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'review_detail_screen.dart';

class ShowReviewsScreen extends StatefulWidget {
  final int showId;
  final String showName;
  final String? posterPath;

  const ShowReviewsScreen({super.key, required this.showId, required this.showName, this.posterPath});

  @override
  State<ShowReviewsScreen> createState() => _ShowReviewsScreenState();
}

class _ShowReviewsScreenState extends State<ShowReviewsScreen> with SingleTickerProviderStateMixin {
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
        reviews.sort((a, b) => DateTime.parse(b['created_at']).compareTo(DateTime.parse(a['created_at'])));
      } else {
        reviews.sort((a, b) {
          int countA = a['comment_likes'] != null && a['comment_likes'].isNotEmpty ? a['comment_likes'][0]['count'] : 0;
          int countB = b['comment_likes'] != null && b['comment_likes'].isNotEmpty ? b['comment_likes'][0]['count'] : 0;
          return countB.compareTo(countA);
        });
      }

      // 2. Friends sekmesi için takip ettiklerimi filtrele
      List fReviews = [];
      if (myId != null) {
        final followingRes = await _supabase.from('follows').select('following_id').eq('follower_id', myId);
        final followingIds = (followingRes as List).map((f) => f['following_id']).toList();
        fReviews = reviews.where((r) => followingIds.contains(r['user_id'])).toList();
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
      backgroundColor: const Color(0xFF14181C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14181C),
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            const Text("Reviews of", style: TextStyle(fontSize: 12, color: Colors.white54)),
            Text(widget.showName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          // SIRALAMA BUTONU
          IconButton(
            icon: Icon(Icons.sort, color: _sortBy == 'likes' ? const Color(0xFF00E054) : Colors.white),
            onPressed: _showSortMenu,
          )
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.white10,
          tabs: const [Tab(text: "Everyone"), Tab(text: "Friends")],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E054)))
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
      backgroundColor: const Color(0xFF1E2329),
      context: context,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.access_time, color: Colors.white),
            title: const Text("Newest First", style: TextStyle(color: Colors.white)),
            onTap: () { setState(() => _sortBy = 'newest'); Navigator.pop(context); _fetchReviews(); },
          ),
          ListTile(
            leading: const Icon(Icons.favorite, color: Colors.white),
            title: const Text("Most Liked", style: TextStyle(color: Colors.white)),
            onTap: () { setState(() => _sortBy = 'likes'); Navigator.pop(context); _fetchReviews(); },
          ),
        ],
      ),
    );
  }

  Widget _buildReviewList(List reviews) {
    if (reviews.isEmpty) return const Center(child: Text("No reviews yet.", style: TextStyle(color: Colors.white24)));
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: reviews.length,
      separatorBuilder: (c, i) => const Divider(color: Colors.white10, height: 32),
      itemBuilder: (context, index) {
        final r = reviews[index];
        return _buildReviewItem(r);
      },
    );
  }

  Widget _buildReviewItem(Map r) {
    final double rating = (r['rating'] as num).toDouble();
    final int likes = r['comment_likes'] != null && r['comment_likes'].isNotEmpty ? r['comment_likes'][0]['count'] : 0;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ReviewDetailScreen(
          review: r,
          showName: widget.showName,
          posterPath: widget.posterPath
      ))).then((_) => _fetchReviews()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Yıldızlar (Letterboxd stili yeşil)
              Row(
                children: List.generate(5, (i) {
                  double val = rating / 2;
                  if (val >= i + 1) return const Icon(Icons.star, color: Color(0xFF00E054), size: 14);
                  if (val >= i + 0.5) return const Icon(Icons.star_half, color: Color(0xFF00E054), size: 14);
                  return const Icon(Icons.star_border, color: Colors.white24, size: 14);
                }),
              ),
              if (likes > 0) ...[
                const SizedBox(width: 8),
                const Icon(Icons.favorite, color: Colors.orange, size: 12),
              ],
              const Spacer(),
              Text(r['profiles']['username'], style: const TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(width: 8),
              CircleAvatar(radius: 10, backgroundColor: Colors.white10, child: Text(r['profiles']['username'][0].toUpperCase(), style: const TextStyle(fontSize: 8, color: Colors.white))),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            r['content'],
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }
}