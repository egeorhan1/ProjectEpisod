import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'other_profile_screen.dart'; // YENİ: Başka profil sayfasını import ettik
import 'theme/app_colors.dart';
import 'widgets/episod_user_avatar.dart';

class FollowListScreen extends StatefulWidget {
  final String userId;
  final String title;
  final bool isFollowers;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.title,
    required this.isFollowers,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  final _supabase = Supabase.instance.client;
  List users = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchList();
  }

  Future<void> _fetchList() async {
    try {
      final String columnToMatch = widget.isFollowers
          ? 'following_id'
          : 'follower_id';
      final String columnToSelect = widget.isFollowers
          ? 'follower_id'
          : 'following_id';

      final res = await _supabase
          .from('follows')
          .select('profiles!follows_${columnToSelect}_fkey(id, username)')
          .eq(columnToMatch, widget.userId);

      if (mounted) {
        setState(() {
          users = (res as List).map((item) => item['profiles']).toList();
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("List load error: $e");
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
        scrolledUnderElevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            size: 20,
            color: AppColors.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : users.isEmpty
          ? Center(
              child: Text(
                "No ${widget.title.toLowerCase()} yet.",
                style: const TextStyle(color: AppColors.textMuted),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: users.length,
              separatorBuilder: (context, index) =>
                  const Divider(color: AppColors.divider, height: 1),
              itemBuilder: (context, index) {
                final user = users[index];
                final String uName = user['username'] ?? "User";

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: EpisodUserAvatar(username: uName, fontSize: 16),
                  title: Text(
                    uName,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    color: AppColors.textMuted,
                    size: 12,
                  ),

                  // ARTIK BURASI ÇALIŞIYOR!
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) =>
                            OtherUserProfileScreen(userId: user['id']),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
