import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'api_config.dart';
import 'show_credits_screen.dart';
import 'episode_detail_screen.dart';
import 'forum_screen.dart';
import 'show_reviews_screen.dart';

class ShowDetailScreen extends StatefulWidget {
  final Map show;
  const ShowDetailScreen({super.key, required this.show});

  @override
  State<ShowDetailScreen> createState() => _ShowDetailScreenState();
}

class _ShowDetailScreenState extends State<ShowDetailScreen> {
  final _supabase = Supabase.instance.client;
  Map? fullDetails;
  List episodes = [];
  List seriesCast = [];
  int selectedSeasonNumber = 1;

  bool isInitialLoading = true;
  bool isEpisodesLoading = true;
  bool isLiked = false;
  bool isWatched = false;

  // Puanlama Sistemi Değişkenleri
  double showEpoint = 0.0;
  double myRating = 0.0;
  String myReviewContent = "";
  int? myReviewId;
  List<int> ratingDistribution = List.filled(10, 0);
  int totalRatingsCount = 0;

  Color activeColor = const Color(0xFF14181C);

  @override
  void initState() {
    super.initState();
    _loadAllPageData();
  }

  // --- TÜM SAYFAYI YENİLEYEN ANA SİSTEM ---
  Future<void> _loadAllPageData() async {
    await Future.wait([
      _checkStatus(),
      _fetchShowEpoint(),
      fetchFullDetails(),
      fetchSeriesCast(),
      _generatePalette(),
    ]);
    if (mounted) setState(() => isInitialLoading = false);
  }

  // --- GRAFİK VERİLERİNİ ÇEKER ---
  Future<void> _fetchShowEpoint() async {
    try {
      final res = await _supabase
          .from('comments')
          .select('rating')
          .eq('show_id', widget.show['id'])
          .filter('season_number', 'is', null)
          .filter('episode_number', 'is', null)
          .not('rating', 'is', null);

      List<int> dist = List.filled(10, 0);
      double total = 0;

      if (res.isNotEmpty) {
        for (var item in res) {
          double r = (item['rating'] as num).toDouble();
          total += r;
          int index = r.round() - 1;
          if (index >= 0 && index < 10) dist[index]++;
        }
      }
      if (mounted) {
        setState(() {
          showEpoint = res.isNotEmpty ? (total / res.length) : 0.0;
          ratingDistribution = dist;
          totalRatingsCount = res.length;
        });
      }
    } catch (e) { debugPrint("Epoint error: $e"); }
  }

  // --- KULLANICI DURUMUNU ÇEKER ---
  Future<void> _checkStatus() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    try {
      final results = await Future.wait<dynamic>([
        _supabase.from('liked_shows').select().eq('user_id', user.id).eq('show_id', widget.show['id']).maybeSingle(),
        _supabase.from('watched_shows').select().eq('user_id', user.id).eq('show_id', widget.show['id']).maybeSingle(),
        _supabase.from('comments')
            .select()
            .eq('user_id', user.id)
            .eq('show_id', widget.show['id'])
            .filter('season_number', 'is', null)
            .filter('episode_number', 'is', null)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle()
      ]);

      if (mounted) {
        setState(() {
          isLiked = results[0] != null;
          isWatched = results[1] != null;

          final userReview = results[2] as Map<String, dynamic>?;
          if (userReview != null) {
            myRating = (userReview['rating'] as num).toDouble();
            myReviewContent = userReview['content'] ?? "";
            myReviewId = userReview['id'];
          } else {
            myRating = 0.0;
            myReviewContent = "";
            myReviewId = null;
          }
        });
      }
    } catch (e) { debugPrint("Status error: $e"); }
  }

  Future<void> fetchFullDetails() async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/tv/${widget.show['id']}?api_key=${ApiConfig.apiKey}');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        if (mounted) {
          setState(() {
            fullDetails = data;
            if (fullDetails!['seasons'].isNotEmpty) {
              selectedSeasonNumber = fullDetails!['seasons'][0]['season_number'];
              fetchEpisodes(selectedSeasonNumber);
            }
          });
        }
      }
    } catch (e) { debugPrint("Details error: $e"); }
  }

  Future<void> fetchEpisodes(int sNum) async {
    setState(() => isEpisodesLoading = true);
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/tv/${widget.show['id']}/season/$sNum?api_key=${ApiConfig.apiKey}');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        if (mounted) setState(() { episodes = json.decode(res.body)['episodes']; isEpisodesLoading = false; });
      }
    } catch (e) { if (mounted) setState(() => isEpisodesLoading = false); }
  }

  Future<void> fetchSeriesCast() async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/tv/${widget.show['id']}/aggregate_credits?api_key=${ApiConfig.apiKey}');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        if (mounted) setState(() => seriesCast = json.decode(res.body)['cast'].take(12).toList());
      }
    } catch (e) { debugPrint("Cast error: $e"); }
  }

  Future<void> _generatePalette() async {
    if (widget.show['poster_path'] == null) return;
    try {
      final p = await PaletteGenerator.fromImageProvider(CachedNetworkImageProvider("https://image.tmdb.org/t/p/w342${widget.show['poster_path']}"));
      if (mounted) setState(() => activeColor = p.dominantColor?.color.withOpacity(0.2) ?? const Color(0xFF14181C));
    } catch (e) { debugPrint("Palette error: $e"); }
  }

  void _openReviewModal(BuildContext context, int showId, String showName) {
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(myReviewId != null ? "Edit Your Review" : "Rate & Review $showName",
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                const SizedBox(height: 20),
                const Text("Your Rating", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
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
                        'show_id': showId,
                        'content': reviewController.text.trim().isEmpty ? "Rated $currentRating stars" : reviewController.text.trim(),
                        'rating': currentRating * 2,
                        'season_number': null,
                        'episode_number': null,
                      };
                      try {
                        await _supabase.from('comments').upsert(data);
                        await _loadAllPageData(); // ANLIK GÜNCELLEME KİLİDİ
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Review updated!"), backgroundColor: Color(0xFF00E054)));
                        }
                      } catch (e) { debugPrint("Upsert Error: $e"); }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E054), minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text(myReviewId != null ? "UPDATE REVIEW" : "SAVE REVIEW", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
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
      backgroundColor: const Color(0xFF14181C),
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [activeColor.withOpacity(0.3), const Color(0xFF14181C)], stops: const [0.0, 0.4]))),
          RefreshIndicator(
            onRefresh: _loadAllPageData,
            color: const Color(0xFF00E054),
            backgroundColor: const Color(0xFF14181C),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  expandedHeight: 280,
                  pinned: true,
                  elevation: 0,
                  backgroundColor: const Color(0xFF14181C),
                  // --- YEŞİL OLMA SORUNUNU ÇÖZEN SATIRLAR ---
                  surfaceTintColor: Colors.transparent,
                  scrolledUnderElevation: 0,
                  // -----------------------------------------
                  leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20), onPressed: () => Navigator.pop(context)),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(fit: StackFit.expand, children: [
                      if (widget.show['backdrop_path'] != null) CachedNetworkImage(imageUrl: "https://image.tmdb.org/t/p/w780${widget.show['backdrop_path']}", fit: BoxFit.cover),
                      Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF14181C).withOpacity(0.85), Colors.transparent, const Color(0xFF14181C)], stops: const [0.0, 0.4, 1.0])))
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 50.0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _buildHeader(),
                      const SizedBox(height: 32),
                      _buildRatingsSection(),
                      const SizedBox(height: 32),
                      _sectionHeader("SERIES CAST", () => Navigator.push(context, MaterialPageRoute(builder: (c) => ShowCreditsScreen(showId: widget.show['id'], showName: widget.show['name'])))),
                      _buildCastList(),
                      const SizedBox(height: 32),
                      _buildCommunitySection(),
                      const SizedBox(height: 32),
                      const Text("SELECT SEASON", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2)),
                      const SizedBox(height: 12),
                      _buildSeasonPicker(),
                      const SizedBox(height: 24),
                      _buildEpisodeList(),
                    ]),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    String releaseYear = (fullDetails != null && fullDetails!['first_air_date'] != null && fullDetails!['first_air_date'] != "") ? " (${fullDetails!['first_air_date'].split('-')[0]})" : "";
    return Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: "https://image.tmdb.org/t/p/w342${widget.show['poster_path']}", height: 120)),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("${widget.show['name']}$releaseYear", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 8),
        Row(children: [const Icon(Icons.star, color: Colors.amber, size: 14), const SizedBox(width: 4), Text(widget.show['vote_average']?.toStringAsFixed(1) ?? 'N/A', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 12),
        Row(children: [
          _actionBtn(isLiked ? Icons.favorite : Icons.favorite_border, isLiked ? Colors.red : Colors.white54, _toggleLike),
          const SizedBox(width: 16),
          _actionBtn(isWatched ? Icons.check_circle : Icons.visibility_outlined, isWatched ? const Color(0xFF00E054) : Colors.white54, _toggleWatched),
          const SizedBox(width: 16),
          _actionBtn(Icons.star_rate_rounded, myRating > 0 ? const Color(0xFF00E054) : Colors.amber, () => _openReviewModal(context, widget.show['id'], widget.show['name'])),
        ])
      ]))
    ]);
  }

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
          Text(showEpoint > 0 ? (showEpoint / 2).toStringAsFixed(1) : "0.0", style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w400)),
          Row(children: List.generate(5, (index) { double val = showEpoint / 2; IconData i = (val >= index + 1) ? Icons.star : (val >= index + 0.5 ? Icons.star_half : Icons.star_border); return Icon(i, color: const Color(0xFF00E054), size: 10); }))
        ])
      ]),
      if (myRating > 0) ...[
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: const Color(0xFF1E2329), borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.person, color: Colors.white54, size: 16), const SizedBox(width: 12), Expanded(child: Text(myReviewContent != "" ? myReviewContent : "You rated this show", style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)), Row(children: List.generate(5, (index) { double val = myRating / 2; IconData i = (val >= index + 1) ? Icons.star : (val >= index + 0.5 ? Icons.star_half : Icons.star_border); return Icon(i, color: Colors.white, size: 12); }))] ))
      ]
    ]);
  }

  Widget _buildCommunitySection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("COMMUNITY", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2)), const SizedBox(height: 16), Row(children: [Expanded(child: _communityBtn("FORUM", Icons.forum_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (c) => ForumScreen(showId: widget.show['id'], showName: widget.show['name']))))), const SizedBox(width: 12), Expanded(child: _communityBtn("REVIEWS", Icons.rate_review_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (c) => ShowReviewsScreen(showId: widget.show['id'], showName: widget.show['name'], posterPath: widget.show['poster_path'])))))] )]);

  Widget _communityBtn(String title, IconData icon, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white10)), child: Column(children: [Icon(icon, color: const Color(0xFF00E054), size: 20), const SizedBox(height: 6), Text(title, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))])));

  Widget _buildEpisodeList() {
    if (isEpisodesLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF00E054)));
    return ListView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: episodes.length,
        itemBuilder: (context, i) {
          final ep = episodes[i];
          String d = ep['air_date'] ?? "";
          if (d.contains('-')) { var p = d.split('-'); d = "${p[2]}.${p[1]}.${p[0]}"; }
          return ListTile(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => EpisodeDetailScreen(episode: ep, showName: widget.show['name'], showId: widget.show['id'], seasonNumber: selectedSeasonNumber))),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: Text("${ep['episode_number']}", style: const TextStyle(color: Color(0xFF00E054), fontWeight: FontWeight.bold)),
            title: Text(ep['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            subtitle: Text(d, style: const TextStyle(color: Colors.white30, fontSize: 11)),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 12),
          );
        }
    );
  }

  Widget _actionBtn(IconData i, Color c, VoidCallback t) => GestureDetector(onTap: t, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)), child: Icon(i, color: c, size: 20)));
  Widget _sectionHeader(String t, VoidCallback o) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(t, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2)), GestureDetector(onTap: o, child: const Text("View All", style: TextStyle(color: Color(0xFF00E054), fontWeight: FontWeight.bold, fontSize: 10)))]);
  Widget _buildCastList() => SizedBox(height: 120, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: seriesCast.length, itemBuilder: (context, i) { final a = seriesCast[i]; return Container(width: 80, margin: const EdgeInsets.only(right: 12, top: 12), child: Column(children: [ClipOval(child: CachedNetworkImage(imageUrl: "https://image.tmdb.org/t/p/w185${a['profile_path']}", width: 55, height: 55, fit: BoxFit.cover, errorWidget: (c,u,e) => Container(color: Colors.white10, child: const Icon(Icons.person, color: Colors.white24)))), const SizedBox(height: 8), Text(a['name'], maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white70), overflow: TextOverflow.ellipsis)])); }));
  Widget _buildSeasonPicker() { final seasons = fullDetails?['seasons'] ?? []; return SizedBox(height: 35, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: seasons.length, itemBuilder: (context, i) { final s = seasons[i]; final isSel = selectedSeasonNumber == s['season_number']; return GestureDetector(onTap: () { setState(() => selectedSeasonNumber = s['season_number']); fetchEpisodes(s['season_number']); }, child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: isSel ? const Color(0xFF00E054) : const Color(0xFF2C3440), borderRadius: BorderRadius.circular(20)), alignment: Alignment.center, child: Text("S${s['season_number']}", style: TextStyle(color: isSel ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 11)))); })); }

  Future<void> _toggleLike() async {
    final user = _supabase.auth.currentUser; if (user == null) return;
    if (isLiked) await _supabase.from('liked_shows').delete().eq('user_id', user.id).eq('show_id', widget.show['id']);
    else await _supabase.from('liked_shows').insert({'user_id': user.id, 'show_id': widget.show['id'], 'show_name': widget.show['name'], 'poster_path': widget.show['poster_path']});
    setState(() => isLiked = !isLiked);
  }

  Future<void> _toggleWatched() async {
    final user = _supabase.auth.currentUser; if (user == null) return;
    if (isWatched) await _supabase.from('watched_shows').delete().eq('user_id', user.id).eq('show_id', widget.show['id']);
    else await _supabase.from('watched_shows').insert({'user_id': user.id, 'show_id': widget.show['id'], 'show_name': widget.show['name'], 'poster_path': widget.show['poster_path']});
    setState(() => isWatched = !isWatched);
  }
}