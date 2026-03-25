import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'forum_screen.dart';

class EpisodeDetailScreen extends StatefulWidget {
  final Map episode;
  final String showName;
  final int showId;
  final int seasonNumber;

  const EpisodeDetailScreen({
    super.key,
    required this.episode,
    required this.showName,
    required this.showId,
    required this.seasonNumber
  });

  @override
  State<EpisodeDetailScreen> createState() => _EpisodeDetailScreenState();
}

class _EpisodeDetailScreenState extends State<EpisodeDetailScreen> {
  final _supabase = Supabase.instance.client;
  bool isInitialLoading = true;
  bool isWatched = false;

  // Puanlama Sistemi Değişkenleri
  double averageEpoint = 0.0;
  double myRating = 0.0;
  String myReviewContent = "";
  List<int> ratingDistribution = List.filled(10, 0);
  int totalRatingsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  // --- TÜM VERİLERİ YÜKLE ---
  Future<void> _loadAllData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => isInitialLoading = false);
      return;
    }

    try {
      final results = await Future.wait<dynamic>([
        // 1. İzlenme Durumu
        _supabase.from('watched_episodes').select().eq('user_id', user.id).eq('show_id', widget.showId).eq('season_number', widget.seasonNumber).eq('episode_number', widget.episode['episode_number']).maybeSingle(),

        // 2. Grafik ve Ortalama için Tüm Puanlar
        _supabase.from('comments')
            .select('rating')
            .eq('show_id', widget.showId)
            .eq('season_number', widget.seasonNumber)
            .eq('episode_number', widget.episode['episode_number'])
            .not('rating', 'is', null),

        // 3. Benim Puanım/Yorumum
        _supabase.from('comments')
            .select()
            .eq('user_id', user.id)
            .eq('show_id', widget.showId)
            .eq('season_number', widget.seasonNumber)
            .eq('episode_number', widget.episode['episode_number'])
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
      ]);

      final allRatings = results[1] as List;
      List<int> dist = List.filled(10, 0);
      double total = 0;
      if (allRatings.isNotEmpty) {
        for (var item in allRatings) {
          double r = (item['rating'] as num).toDouble();
          total += r;
          int index = r.round() - 1;
          if (index >= 0 && index < 10) dist[index]++;
        }
      }

      if (mounted) {
        setState(() {
          isWatched = results[0] != null;
          averageEpoint = allRatings.isNotEmpty ? (total / allRatings.length) : 0.0;
          ratingDistribution = dist;
          totalRatingsCount = allRatings.length;

          final userReview = results[2] as Map<String, dynamic>?;
          if (userReview != null) {
            myRating = (userReview['rating'] as num).toDouble();
            myReviewContent = userReview['content'] ?? "";
          } else {
            myRating = 0.0; myReviewContent = "";
          }
          isInitialLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Load Error: $e");
      if (mounted) setState(() => isInitialLoading = false);
    }
  }

  Future<void> _toggleWatched() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      if (isWatched) {
        await _supabase.from('watched_episodes').delete().eq('user_id', user.id).eq('show_id', widget.showId).eq('season_number', widget.seasonNumber).eq('episode_number', widget.episode['episode_number']);
      } else {
        await _supabase.from('watched_episodes').insert({'user_id': user.id, 'show_id': widget.showId, 'season_number': widget.seasonNumber, 'episode_number': widget.episode['episode_number']});
      }
      setState(() => isWatched = !isWatched);
    } catch (e) { debugPrint("EP Watch error: $e"); }
  }

  void _openReviewModal(BuildContext context) {
    double currentRating = myRating > 0 ? myRating / 2 : 0.0;
    final TextEditingController reviewController = TextEditingController(text: myReviewContent);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E2329),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 24),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(myRating > 0 ? "Edit Review" : "Rate Episode", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return GestureDetector(
                      onTapDown: (TapDownDetails details) {
                        setModalState(() {
                          if (details.localPosition.dx < 20) currentRating = index + 0.5;
                          else currentRating = index + 1.0;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Icon(
                          currentRating >= index + 1 ? Icons.star : currentRating >= index + 0.5 ? Icons.star_half : Icons.star_border,
                          color: currentRating > index ? const Color(0xFF00E054) : Colors.white24,
                          size: 40,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                Text("$currentRating Stars", style: const TextStyle(color: Color(0xFF00E054), fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFF14181C), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                  child: TextField(
                    controller: reviewController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(hintText: "Review...", hintStyle: TextStyle(color: Colors.white24), border: InputBorder.none),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    if (currentRating == 0) return;
                    final user = _supabase.auth.currentUser;
                    if (user != null) {
                      final data = {
                        'user_id': user.id,
                        'show_id': widget.showId,
                        'season_number': widget.seasonNumber,
                        'episode_number': widget.episode['episode_number'],
                        'content': reviewController.text.trim().isEmpty ? "Rated $currentRating stars" : reviewController.text.trim(),
                        'rating': currentRating * 2,
                      };

                      await _supabase.from('comments').upsert(data);
                      await _loadAllData(); // Anlık güncelleme

                      if (context.mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Success!"), backgroundColor: Color(0xFF00E054)));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E054), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: const Text("SAVE", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 30),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isInitialLoading) return const Scaffold(backgroundColor: Color(0xFF14181C), body: Center(child: CircularProgressIndicator(color: Color(0xFF00E054))));
    return Scaffold(
      backgroundColor: const Color(0xFF14181C), extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
        title: Text("S${widget.seasonNumber}E${widget.episode['episode_number']}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        centerTitle: true,
        flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent]))),
      ),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildHeader(),
          Padding(padding: const EdgeInsets.fromLTRB(24, 10, 24, 100), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildScores(), // Sadece TMDB puanını gösterir
            const SizedBox(height: 24),
            Row(children: [
              _actionBtn(isWatched ? Icons.check_circle : Icons.visibility_outlined, isWatched ? const Color(0xFF00E054) : Colors.white, _toggleWatched, isWatched ? "Watched" : "Watch"),
              const SizedBox(width: 12),
              _actionBtn(Icons.star_rate_rounded, myRating > 0 ? const Color(0xFF00E054) : Colors.amber, () => _openReviewModal(context), "Rate"),
            ]),
            const SizedBox(height: 32),
            _buildRatingsSection(), // Grafik + Ortalama EPOINT + Kişisel Puan Kutusu
            const SizedBox(height: 32),
            _buildOverview(),
            const SizedBox(height: 40),
            _buildCommunitySection(),
          ])),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Stack(children: [
      widget.episode['still_path'] != null
          ? CachedNetworkImage(imageUrl: "https://image.tmdb.org/t/p/w780${widget.episode['still_path']}", width: double.infinity, height: 280, fit: BoxFit.cover)
          : Container(height: 280, width: double.infinity, color: Colors.white10, child: const Icon(Icons.movie, color: Colors.white24, size: 50)),
      Positioned(bottom: 0, left: 0, right: 0, child: Container(height: 100, decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xFF14181C)])))),
    ]);
  }

  // SADECE TMDB SKORU
  Widget _buildScores() => Row(children: [
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("TMDB", style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Row(children: [
        const Icon(Icons.star, color: Colors.amber, size: 16),
        const SizedBox(width: 8),
        Text("${widget.episode['vote_average']?.toStringAsFixed(1)}", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
      ])
    ])
  ]);

  // TÜM PUANLAMA BÖLÜMÜ (Show Detail ile aynı stil)
  Widget _buildRatingsSection() {
    int maxCount = ratingDistribution.reduce(max); if (maxCount == 0) maxCount = 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("RATINGS", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1.5)),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const Padding(padding: EdgeInsets.only(bottom: 2.0, right: 8.0), child: Icon(Icons.star, color: Color(0xFF00E054), size: 12)),
        Expanded(child: SizedBox(height: 35, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(10, (index) {
          double heightPercent = ratingDistribution[index] / maxCount;
          return Expanded(child: Container(margin: const EdgeInsets.only(right: 1), height: (30 * heightPercent) + 4, decoration: const BoxDecoration(color: Color(0xFF384250), borderRadius: BorderRadius.vertical(top: Radius.circular(2)))) );
        })))),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(averageEpoint > 0 ? (averageEpoint / 2).toStringAsFixed(1) : "0.0", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w400)),
          Row(children: List.generate(5, (index) { double val = averageEpoint / 2; IconData i = (val >= index + 1) ? Icons.star : (val >= index + 0.5 ? Icons.star_half : Icons.star_border); return Icon(i, color: const Color(0xFF00E054), size: 10); }))
        ])
      ]),
      if (myRating > 0) ...[
        const SizedBox(height: 16),
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: const Color(0xFF1E2329), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.person, color: Colors.white54, size: 16),
              const SizedBox(width: 12),
              Expanded(child: Text(myReviewContent != "" ? myReviewContent : "You rated this episode", style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
              Row(children: List.generate(5, (index) { double val = myRating / 2; IconData i = (val >= index + 1) ? Icons.star : (val >= index + 0.5 ? Icons.star_half : Icons.star_border); return Icon(i, color: Colors.white, size: 12); }))
            ])
        )
      ]
    ]);
  }

  Widget _buildOverview() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("OVERVIEW", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2)), const SizedBox(height: 12), Text(widget.episode['overview'] != "" ? widget.episode['overview'] : "No summary available.", style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.6))]);

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap, String label) => Expanded(child: GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: const Color(0xFF1E2329), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, color: color, size: 18), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))]))));

  Widget _buildCommunitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("COMMUNITY", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _communityBtn("FORUM", Icons.forum_outlined, () {
              Navigator.push(context, MaterialPageRoute(builder: (c) => ForumScreen(showId: widget.showId, showName: widget.showName, seasonNumber: widget.seasonNumber, episodeNumber: widget.episode['episode_number'])));
            })),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }

  Widget _communityBtn(String title, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)),
        child: Column(children: [Icon(icon, color: const Color(0xFF00E054), size: 24), const SizedBox(height: 8), Text(title, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1))]),
      ),
    );
  }
}