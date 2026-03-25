import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'api_config.dart';
import 'other_profile_screen.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _supabase = Supabase.instance.client;
  List feedItems = [];
  bool isLoading = true;

  // YENİ: Benim takip ettiğim kişilerin listesini hafızada tutuyoruz ki butonu ona göre çizelim
  List<String> myFollowingIds = [];

  @override
  void initState() {
    super.initState();
    _fetchMixedFeed();
  }

  Future<void> _fetchMixedFeed() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      List unifiedList = [];

      // 1. Kimi takip ettiğimi bul ve hafızaya al
      final followingRes = await _supabase.from('follows').select('following_id').eq('follower_id', myId);
      myFollowingIds = (followingRes as List).map((f) => f['following_id'].toString()).toList();

      // 2. BANA GELEN BİLDİRİMLERİ (TAKİP VS.) ÇEK
      final activitiesRes = await _supabase
          .from('activities')
          .select('*, profiles!activities_actor_id_fkey(id, username)')
          .eq('user_id', myId)
          .order('created_at', ascending: false)
          .limit(20);

      for (var act in (activitiesRes as List)) {
        unifiedList.add({
          'type': 'notification',
          'action': act['action_type'],
          'user': act['profiles']['username'],
          'user_id': act['profiles']['id'],
          'raw_time': DateTime.parse(act['created_at']).toLocal(),
        });
      }

      // 3. TAKİP ETTİĞİM KİŞİLERİN İNCELEMELERİNİ ÇEK
      if (myFollowingIds.isNotEmpty) {
        final reviews = await _supabase
            .from('comments')
            .select('*, profiles!comments_user_id_fkey(id, username)')
            .inFilter('user_id', myFollowingIds)
            .isFilter('parent_id', null)
            .order('created_at', ascending: false)
            .limit(20);

        for (var item in (reviews as List)) {
          final tmdbRes = await http.get(Uri.parse('${ApiConfig.baseUrl}/tv/${item['show_id']}?api_key=${ApiConfig.apiKey}&language=en-US'));
          String? poster;
          String showName = "Show";

          if (tmdbRes.statusCode == 200) {
            final data = json.decode(tmdbRes.body);
            poster = data['poster_path'];
            showName = data['name'];
          }

          unifiedList.add({
            'type': 'review',
            'user': item['profiles']['username'],
            'user_id': item['profiles']['id'],
            'content': item['content'],
            'show_name': showName,
            'poster': poster,
            'raw_time': DateTime.parse(item['created_at']).toLocal(),
          });
        }
      }

      // 4. LİSTELERİ BİRLEŞTİR VE TARİHE GÖRE SIRALA
      unifiedList.sort((a, b) => b['raw_time'].compareTo(a['raw_time']));

      for (var item in unifiedList) {
        final Duration diff = DateTime.now().difference(item['raw_time']);
        item['time_ago'] = diff.inDays > 0 ? "${diff.inDays}d ago" : diff.inHours > 0 ? "${diff.inHours}h ago" : diff.inMinutes > 0 ? "${diff.inMinutes}m ago" : "Just now";
      }

      if (mounted) setState(() { feedItems = unifiedList; isLoading = false; });
    } catch (e) {
      debugPrint("Feed error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // YENİ: GERİ TAKİP ETME (FOLLOW BACK) FONKSİYONU
  Future<void> _followUserBack(String targetUserId) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      // Takip et
      await _supabase.from('follows').insert({
        'follower_id': myId,
        'following_id': targetUserId
      });
      // Bildirim yolla
      await _supabase.from('activities').insert({
        'user_id': targetUserId,
        'actor_id': myId,
        'action_type': 'follow'
      });

      // Anında UI güncelle (Tiki çıkart)
      setState(() {
        myFollowingIds.add(targetUserId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Followed back!"), duration: Duration(seconds: 2)));
      }
    } catch (e) {
      debugPrint("Follow back error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF14181C),
      appBar: AppBar(
        title: const Text("Recent Activity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 1.2)),
        backgroundColor: const Color(0xFF14181C),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E054)))
          : feedItems.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: _fetchMixedFeed,
        color: const Color(0xFF00E054),
        backgroundColor: const Color(0xFF1E2329),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          itemCount: feedItems.length,
          separatorBuilder: (c, i) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Divider(color: Colors.white10, height: 1),
          ),
          itemBuilder: (context, index) {
            final item = feedItems[index];
            if (item['type'] == 'notification') {
              return _buildNotificationItem(item);
            } else {
              return _buildReviewItem(item);
            }
          },
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.notifications_none, size: 60, color: Colors.white24),
          const SizedBox(height: 16),
          const Text("No recent activity", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Follow people to see their reviews,\nor wait for someone to follow you.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
        ],
      ),
    );
  }

  // --- ARTIK ÇALIŞAN TAKİP BİLDİRİMİ TASARIMI ---
  Widget _buildNotificationItem(Map item) {
    final String targetUserId = item['user_id'];
    final bool isFollowingBack = myFollowingIds.contains(targetUserId);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => OtherUserProfileScreen(userId: targetUserId))),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF2C3440),
              child: Text(item['user'][0].toUpperCase(), style: const TextStyle(color: Color(0xFF00E054), fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                    children: [
                      TextSpan(text: "${item['user']} ", style: const TextStyle(fontWeight: FontWeight.bold)),
                      const TextSpan(text: "started following you.", style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(item['time_ago'], style: const TextStyle(color: Colors.white30, fontSize: 12)),
              ],
            ),
          ),

          // YENİ: AKILLI BUTON
          if (isFollowingBack)
            const Icon(Icons.check_circle, color: Colors.white24, size: 22) // Zaten takip ediyorsan sönük tik çıkar
          else
            IconButton(
              icon: const Icon(Icons.person_add_alt_1, color: Color(0xFF00E054), size: 24),
              onPressed: () => _followUserBack(targetUserId), // Tıklayınca anında geri takip et!
            ),
        ],
      ),
    );
  }

  // --- İNCELEME (REVIEW) TASARIMI (Aynen korundu) ---
  Widget _buildReviewItem(Map item) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => OtherUserProfileScreen(userId: item['user_id']))),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF2C3440),
              child: Text(item['user'][0].toUpperCase(), style: const TextStyle(color: Color(0xFF00E054), fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text("${item['user']} ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                    const Text("reviewed ", style: TextStyle(color: Colors.white54, fontSize: 14)),
                    Text("${item['show_name']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(item['time_ago'], style: const TextStyle(color: Colors.white30, fontSize: 12)),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E2329),
                    borderRadius: const BorderRadius.only(topRight: Radius.circular(16), bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.format_quote_rounded, color: Color(0xFF00E054), size: 18),
                      const SizedBox(height: 4),
                      Text(item['content'], style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, fontWeight: FontWeight.w400)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: "https://image.tmdb.org/t/p/w154${item['poster']}",
                width: 60, height: 90, fit: BoxFit.cover,
                placeholder: (c, u) => Container(width: 60, height: 90, color: const Color(0xFF1E2329)),
                errorWidget: (c, u, e) => Container(width: 60, height: 90, color: const Color(0xFF1E2329), child: const Icon(Icons.tv, size: 20, color: Colors.white24)),
              ),
            ),
          )
        ],
      ),
    );
  }
}