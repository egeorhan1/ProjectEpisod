import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_colors.dart';

class ReviewDetailScreen extends StatefulWidget {
  final Map review;
  final String showName;
  final String? posterPath;

  const ReviewDetailScreen({
    super.key,
    required this.review,
    required this.showName,
    this.posterPath,
  });

  @override
  State<ReviewDetailScreen> createState() => _ReviewDetailScreenState();
}

class _ReviewDetailScreenState extends State<ReviewDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool isLiked = false;
  int likeCount = 0;
  bool isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _checkLikeStatus();
  }

  // --- HATASIZ BEĞENİ DURUMU SORGUSU ---
  Future<void> _checkLikeStatus() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;

    try {
      // Future.wait'e <Future<dynamic>> tipini vererek hatayı çözüyoruz
      final results = await Future.wait<dynamic>([
        // 1. Ben beğendim mi?
        _supabase
            .from('comment_likes')
            .select()
            .eq('user_id', myId)
            .eq('comment_id', widget.review['id'])
            .maybeSingle(),

        // 2. Toplam beğeni sayısı (Hata veren FetchOptions'ı sildik, en sade hali bu)
        _supabase
            .from('comment_likes')
            .select('*')
            .eq('comment_id', widget.review['id'])
            .count(CountOption.exact),
      ]);

      if (mounted) {
        setState(() {
          isLiked = results[0] != null;
          // results[1] artık bir PostgrestResponse tipinde döner
          likeCount = (results[1] as PostgrestResponse).count ?? 0;
        });
      }
    } catch (e) {
      debugPrint("Like status error: $e");
    }
  }

  // --- BEĞENİ BUTONU MANTIĞI ---
  Future<void> _toggleLike() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || isActionLoading) return;

    setState(() => isActionLoading = true);

    try {
      if (isLiked) {
        await _supabase
            .from('comment_likes')
            .delete()
            .eq('user_id', myId)
            .eq('comment_id', widget.review['id']);

        setState(() {
          isLiked = false;
          likeCount--;
        });
      } else {
        await _supabase.from('comment_likes').insert({
          'user_id': myId,
          'comment_id': widget.review['id'],
        });

        setState(() {
          isLiked = true;
          likeCount++;
        });
      }
    } catch (e) {
      debugPrint("Toggle like error: $e");
    } finally {
      if (mounted) setState(() => isActionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 10 üzerinden olan puanı 5 yıldızlı sisteme çevir (Görsel amaçlı)
    final double rating = (widget.review['rating'] as num).toDouble();
    final String username = widget.review['profiles']['username'] ?? "User";

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER: POSTER VE BİLGİLER ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: widget.posterPath != null
                      ? CachedNetworkImage(
                          imageUrl:
                              "https://image.tmdb.org/t/p/w154${widget.posterPath}",
                          width: 100,
                          height: 150,
                          fit: BoxFit.cover,
                          placeholder: (c, u) =>
                              Container(color: AppColors.divider),
                        )
                      : Container(
                          width: 100,
                          height: 150,
                          color: AppColors.divider,
                          child: const Icon(
                            Icons.tv,
                            color: AppColors.textMuted,
                          ),
                        ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.showName,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text(
                            "Review by ",
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            username,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // YILDIZLAR
                      Row(
                        children: List.generate(5, (i) {
                          double val = rating / 2;
                          if (val >= i + 1)
                            return const Icon(
                              Icons.star,
                              color: AppColors.accent,
                              size: 20,
                            );
                          if (val >= i + 0.5)
                            return const Icon(
                              Icons.star_half,
                              color: AppColors.accent,
                              size: 20,
                            );
                          return const Icon(
                            Icons.star_border,
                            color: AppColors.textMuted,
                            size: 20,
                          );
                        }),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),
            const Divider(color: AppColors.divider),
            const SizedBox(height: 24),

            // --- İNCELEME METNİ ---
            Text(
              widget.review['content'],
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                height: 1.6,
                fontWeight: FontWeight.w400,
              ),
            ),

            const SizedBox(height: 80),

            // --- BEĞENİ ALANI ---
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _toggleLike,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isLiked
                            ? AppColors.accentSecondary.withValues(alpha: 0.15)
                            : AppColors.textPrimary.withValues(alpha: 0.05),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isLiked
                              ? AppColors.accentSecondary
                              : AppColors.divider,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked
                            ? AppColors.accentSecondary
                            : AppColors.textSecondary,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    likeCount == 0
                        ? "Be the first to like"
                        : "$likeCount likes",
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
