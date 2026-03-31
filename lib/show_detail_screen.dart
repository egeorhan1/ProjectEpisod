import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_config.dart';
import 'show_credits_screen.dart';
import 'episode_detail_screen.dart';
import 'forum_screen.dart';
import 'show_reviews_screen.dart';
import 'person_detail_screen.dart'; // OYUNCU PROFİLİ EKLENDİ
import 'theme/app_colors.dart'; // YENİ TEMA EKLENDİ

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

  // Ekstra Özellikler
  String? trailerKey;
  Color activeColor = AppColors.background;

  @override
  void initState() {
    super.initState();
    _loadAllPageData();
  }

  Future<void> _loadAllPageData() async {
    await Future.wait([
      _checkStatus(),
      _fetchShowEpoint(),
      fetchFullDetails(),
      fetchSeriesCast(),
      _generatePalette(),
      fetchTrailer(),
    ]);
    if (mounted) setState(() => isInitialLoading = false);
  }

  Future<void> _launchSpotify() async {
    final showName = Uri.encodeComponent("${widget.show['name']} soundtrack");
    final url = Uri.parse("https://open.spotify.com/search/$showName");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> fetchTrailer() async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/tv/${widget.show['id']}/videos?api_key=${ApiConfig.apiKey}');
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final List videos = json.decode(res.body)['results'];
        final trailer = videos.firstWhere(
              (v) => v['type'] == 'Trailer' && v['site'] == 'YouTube',
          orElse: () => videos.firstWhere((v) => v['site'] == 'YouTube', orElse: () => videos.isNotEmpty ? videos.first : null),
        );
        if (mounted && trailer != null) setState(() => trailerKey = trailer['key']);
      }
    } catch (e) { debugPrint("Trailer error: $e"); }
  }

  Future<void> _launchTrailer() async {
    if (trailerKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Trailer not found.")));
      return;
    }
    final url = Uri.parse("https://www.youtube.com/watch?v=$trailerKey");
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _fetchShowEpoint() async {
    try {
      final res = await _supabase.from('comments').select('rating').eq('show_id', widget.show['id']).filter('season_number', 'is', null).filter('episode_number', 'is', null).not('rating', 'is', null);
      List<int> dist = List.filled(10, 0); double total = 0;
      if (res.isNotEmpty) {
        for (var item in res) {
          double r = (item['rating'] as num).toDouble();
          total += r; int index = r.round() - 1;
          if (index >= 0 && index < 10) dist[index]++;
        }
      }
      if (mounted) setState(() { showEpoint = res.isNotEmpty ? (total / res.length) : 0.0; ratingDistribution = dist; totalRatingsCount = res.length; });
    } catch (e) { debugPrint("Epoint error: $e"); }
  }

  Future<void> _checkStatus() async {
    final user = _supabase.auth.currentUser; if (user == null) return;
    try {
      final results = await Future.wait<dynamic>([
        _supabase.from('liked_shows').select().eq('user_id', user.id).eq('show_id', widget.show['id']).maybeSingle(),
        _supabase.from('watched_shows').select().eq('user_id', user.id).eq('show_id', widget.show['id']).maybeSingle(),
        _supabase.from('comments').select().eq('user_id', user.id).eq('show_id', widget.show['id']).filter('season_number', 'is', null).filter('episode_number', 'is', null).order('created_at', ascending: false).limit(1).maybeSingle()
      ]);
      if (mounted) {
        setState(() {
          isLiked = results[0] != null;
          isWatched = results[1] != null;
          final uR = results[2] as Map<String, dynamic>?;
          if (uR != null) {
            myRating = (uR['rating'] as num).toDouble();
            myReviewContent = uR['content'] ?? "";
            myReviewId = uR['id'];
          } else {
            myRating = 0.0; myReviewContent = ""; myReviewId = null;
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
      if (mounted) setState(() => activeColor = p.dominantColor?.color.withOpacity(0.2) ?? AppColors.background);
    } catch (e) { debugPrint("Palette error: $e"); }
  }

  // --- ÖDÜL RADARI HİLESİ ---
  List<String> _detectAwards(String? overview) {
    if (overview == null || overview.isEmpty) return [];
    List<String> awards = [];
    final text = overview.toLowerCase();
    if (text.contains('emmy')) awards.add('Emmy');
    if (text.contains('golden globe')) awards.add('Golden Globe');
    if (text.contains('oscar') || text.contains('academy award')) awards.add('Oscar');
    if (text.contains('bafta')) awards.add('BAFTA');
    return awards;
  }

  void _openReviewModal(BuildContext context, int showId, String showName) {
    double currentRating = myRating > 0 ? myRating / 2 : 0.0;
    final TextEditingController reviewController = TextEditingController(text: myReviewContent);
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 24),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(myReviewId != null ? "Edit Your Review" : "Rate & Review $showName", style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(5, (index) {
                  return GestureDetector(
                    onTapDown: (d) { setModalState(() { if (d.localPosition.dx < 20) currentRating = index + 0.5; else currentRating = index + 1.0; }); },
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Icon(currentRating >= index + 1 ? Icons.star : currentRating >= index + 0.5 ? Icons.star_half : Icons.star_border, color: currentRating > index ? AppColors.accentSecondary : AppColors.divider, size: 40)),
                  );
                })),
                const SizedBox(height: 8),
                Text("$currentRating Stars", style: const TextStyle(color: AppColors.accentSecondary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)), child: TextField(controller: reviewController, maxLines: 4, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14), decoration: const InputDecoration(hintText: "What do you think?", hintStyle: TextStyle(color: AppColors.textMuted), border: InputBorder.none))),
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
                        'episode_number': null
                      };
                      try {
                        // 1. Yorumu/Puanı Kaydet
                        await _supabase.from('comments').upsert(data);

                        // 2. OTOMATİK İZLENDİ İŞARETLE (Eğer işaretli değilse)
                        if (!isWatched) {
                          await _supabase.from('watched_shows').upsert({
                            'user_id': user.id,
                            'show_id': widget.show['id'],
                            'show_name': widget.show['name'],
                            'poster_path': widget.show['poster_path']
                          });
                        }

                        await _loadAllPageData(); // Sayfayı yenile (isWatched true olarak dönecek)

                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: const Text("Review saved & Marked as watched! 📺", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                                  backgroundColor: AppColors.success,
                                  behavior: SnackBarBehavior.floating
                              )
                          );
                        }
                      } catch (e) { debugPrint("Save Error: $e"); }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: Text(myReviewId != null ? "UPDATE REVIEW" : "SAVE REVIEW", style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
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
    if (isInitialLoading) return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator(color: AppColors.accent)));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [activeColor.withOpacity(0.3), AppColors.background], stops: const [0.0, 0.4]))),
          RefreshIndicator(
            onRefresh: _loadAllPageData, color: AppColors.accentSecondary, backgroundColor: AppColors.surface,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar(
                  expandedHeight: 280, pinned: true, elevation: 0, backgroundColor: AppColors.background,
                  surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0,
                  leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.textPrimary, size: 20), onPressed: () => Navigator.pop(context)),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Stack(fit: StackFit.expand, children: [
                      if (widget.show['backdrop_path'] != null) CachedNetworkImage(imageUrl: "https://image.tmdb.org/t/p/w780${widget.show['backdrop_path']}", fit: BoxFit.cover),
                      Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.background.withOpacity(0.85), Colors.transparent, AppColors.background], stops: const [0.0, 0.4, 1.0])))
                    ]),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 50.0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _buildHeader(),
                      const SizedBox(height: 32),
                      _buildOverview(),
                      const SizedBox(height: 32),
                      _buildRatingsSection(),
                      const SizedBox(height: 32),
                      _sectionHeader("SERIES CAST", () => Navigator.push(context, MaterialPageRoute(builder: (c) => ShowCreditsScreen(showId: widget.show['id'], showName: widget.show['name'])))),
                      _buildCastList(),
                      const SizedBox(height: 32),
                      _buildCommunitySection(),
                      const SizedBox(height: 32),
                      const Text("SELECT SEASON", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
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

  // --- UI PARÇALARI ---

  Widget _buildHeader() {
    String releaseYear = (fullDetails != null && fullDetails!['first_air_date'] != null && fullDetails!['first_air_date'] != "") ? " (${fullDetails!['first_air_date'].split('-')[0]})" : "";
    return Row(children: [
      ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: "https://image.tmdb.org/t/p/w342${widget.show['poster_path']}", height: 120)),
      const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text("${widget.show['name']}$releaseYear", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Row(children: [const Icon(Icons.star, color: AppColors.accentSecondary, size: 14), const SizedBox(width: 4), Text(widget.show['vote_average']?.toStringAsFixed(1) ?? 'N/A', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold))]),
        const SizedBox(height: 12),
        Row(children: [
          _actionBtn(isLiked ? Icons.favorite : Icons.favorite_border, isLiked ? AppColors.accent : AppColors.textSecondary, _toggleLike),
          const SizedBox(width: 12),
          _actionBtn(isWatched ? Icons.check_circle : Icons.visibility_outlined, isWatched ? AppColors.success : AppColors.textSecondary, _toggleWatched),
          const SizedBox(width: 12),
          _actionBtn(Icons.star_rate_rounded, myRating > 0 ? AppColors.accentSecondary : AppColors.textSecondary, () => _openReviewModal(context, widget.show['id'], widget.show['name'])),
          const SizedBox(width: 12),
          _actionBtn(Icons.play_circle_fill, AppColors.textPrimary, _launchTrailer),
          const SizedBox(width: 12),
          _actionBtn(Icons.music_note, const Color(0xFF1DB954), _launchSpotify), // Spotify kendi yeşili
        ])
      ]))
    ]);
  }

  // YENİ: ÖZET VE ÖDÜL RADARI
  Widget _buildOverview() {
    final overview = widget.show['overview'] ?? fullDetails?['overview'] ?? "";
    final detectedAwards = _detectAwards(overview);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("OVERVIEW", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        if (detectedAwards.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: detectedAwards.map((a) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.accentSecondary.withOpacity(0.2), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.accentSecondary)),
              child: Text("🏆 $a Mention", style: const TextStyle(color: AppColors.accentSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
            )).toList(),
          ),
          const SizedBox(height: 12),
        ],
        Text(overview != "" ? overview : "No summary available.", style: const TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.5)),
      ],
    );
  }

  Widget _buildRatingsSection() {
    int maxCount = ratingDistribution.reduce(max); if (maxCount == 0) maxCount = 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text("RATINGS", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.5)),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        const Padding(padding: EdgeInsets.only(bottom: 2.0, right: 8.0), child: Icon(Icons.star, color: AppColors.accentSecondary, size: 12)),
        Expanded(child: SizedBox(height: 35, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: List.generate(10, (index) {
          double hP = ratingDistribution[index] / maxCount;
          return Expanded(child: Container(margin: const EdgeInsets.only(right: 1), height: (30 * hP) + 4, decoration: const BoxDecoration(color: AppColors.ratingBar, borderRadius: BorderRadius.vertical(top: Radius.circular(2)))) );
        })))),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(showEpoint > 0 ? (showEpoint / 2).toStringAsFixed(1) : "0.0", style: const TextStyle(color: AppColors.textPrimary, fontSize: 28, fontWeight: FontWeight.w400)),
          Row(children: List.generate(5, (index) { double val = showEpoint / 2; IconData i = (val >= index + 1) ? Icons.star : (val >= index + 0.5 ? Icons.star_half : Icons.star_border); return Icon(i, color: AppColors.accentSecondary, size: 10); }))
        ])
      ]),
      if (myRating > 0) ...[
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)), child: Row(children: [const Icon(Icons.person, color: AppColors.textMuted, size: 16), const SizedBox(width: 12), Expanded(child: Text(myReviewContent != "" ? myReviewContent : "You rated this show", style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)), Row(children: List.generate(5, (index) { double val = myRating / 2; IconData i = (val >= index + 1) ? Icons.star : (val >= index + 0.5 ? Icons.star_half : Icons.star_border); return Icon(i, color: AppColors.textPrimary, size: 12); }))] ))
      ]
    ]);
  }

  Widget _buildCommunitySection() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("COMMUNITY", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)), const SizedBox(height: 16), Row(children: [Expanded(child: _communityBtn("FORUM", Icons.forum_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (c) => ForumScreen(showId: widget.show['id'], showName: widget.show['name']))))), const SizedBox(width: 12), Expanded(child: _communityBtn("REVIEWS", Icons.rate_review_outlined, () => Navigator.push(context, MaterialPageRoute(builder: (c) => ShowReviewsScreen(showId: widget.show['id'], showName: widget.show['name'], posterPath: widget.show['poster_path'])))))] )]);
  Widget _communityBtn(String t, IconData i, VoidCallback o) => GestureDetector(onTap: o, child: Container(padding: const EdgeInsets.symmetric(vertical: 12), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.divider)), child: Column(children: [Icon(i, color: AppColors.accentSecondary, size: 20), const SizedBox(height: 6), Text(t, style: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1))])));

  Widget _buildEpisodeList() {
    if (isEpisodesLoading) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    return ListView.builder(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: episodes.length,
        itemBuilder: (context, i) {
          final ep = episodes[i];
          String d = ep['air_date'] ?? "";
          if (d.contains('-')) { var p = d.split('-'); d = "${p[2]}.${p[1]}.${p[0]}"; }
          return ListTile(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => EpisodeDetailScreen(episode: ep, showName: widget.show['name'], showId: widget.show['id'], seasonNumber: selectedSeasonNumber))),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: Text("${ep['episode_number']}", style: const TextStyle(color: AppColors.accentSecondary, fontWeight: FontWeight.bold)),
            title: Text(ep['name'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
            subtitle: Text(d, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            trailing: const Icon(Icons.arrow_forward_ios, color: AppColors.textMuted, size: 12),
          );
        }
    );
  }

  Widget _actionBtn(IconData i, Color c, VoidCallback t) => GestureDetector(onTap: t, child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(8)), child: Icon(i, color: c, size: 20)));
  Widget _sectionHeader(String t, VoidCallback o) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(t, style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)), GestureDetector(onTap: o, child: Text("View All", style: TextStyle(color: AppColors.accentSecondary, fontWeight: FontWeight.bold, fontSize: 10)))]);

  // YENİ: TIKLANABİLİR CAST LİSTESİ
  Widget _buildCastList() => SizedBox(height: 120, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: seriesCast.length, itemBuilder: (context, i) {
    final a = seriesCast[i];
    return GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => PersonDetailScreen(personId: a['id'], personName: a['name']))),
        child: Container(width: 80, margin: const EdgeInsets.only(right: 12, top: 12), child: Column(children: [ClipOval(child: CachedNetworkImage(imageUrl: "https://image.tmdb.org/t/p/w185${a['profile_path']}", width: 55, height: 55, fit: BoxFit.cover, errorWidget: (c,u,e) => Container(color: AppColors.surface, child: const Icon(Icons.person, color: AppColors.textMuted)))), const SizedBox(height: 8), Text(a['name'], maxLines: 2, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)]))
    );
  }));

  Widget _buildSeasonPicker() { final seasons = fullDetails?['seasons'] ?? []; return SizedBox(height: 35, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: seasons.length, itemBuilder: (context, i) { final s = seasons[i]; final isSel = selectedSeasonNumber == s['season_number']; return GestureDetector(onTap: () { setState(() => selectedSeasonNumber = s['season_number']); fetchEpisodes(s['season_number']); }, child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: isSel ? AppColors.accentSecondary : AppColors.surface, borderRadius: BorderRadius.circular(20)), alignment: Alignment.center, child: Text("S${s['season_number']}", style: TextStyle(color: isSel ? AppColors.background : AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11)))); })); }

  Future<void> _toggleLike() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    bool isAdding = !isLiked;
    try {
      if (isLiked) {
        await _supabase.from('liked_shows').delete().eq('user_id', user.id).eq('show_id', widget.show['id']);
      } else {
        await _supabase.from('liked_shows').insert({'user_id': user.id, 'show_id': widget.show['id'], 'show_name': widget.show['name'], 'poster_path': widget.show['poster_path']});
      }
      setState(() => isLiked = !isLiked);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAdding ? "Added to Favorites! ❤️" : "Removed from Favorites", style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)), backgroundColor: isAdding ? AppColors.accent : AppColors.surface, duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
      }
    } catch (e) { debugPrint("Like error: $e"); }
  }

  Future<void> _toggleWatched() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    bool isAdding = !isWatched;
    try {
      if (isWatched) {
        await _supabase.from('watched_shows').delete().eq('user_id', user.id).eq('show_id', widget.show['id']);
      } else {
        await _supabase.from('watched_shows').insert({'user_id': user.id, 'show_id': widget.show['id'], 'show_name': widget.show['name'], 'poster_path': widget.show['poster_path']});
      }
      setState(() => isWatched = !isWatched);
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isAdding ? "Marked as Watched! 📺" : "Removed from Watched", style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)), backgroundColor: isAdding ? AppColors.success : AppColors.surface, duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
      }
    } catch (e) { debugPrint("Watch error: $e"); }
  }
}