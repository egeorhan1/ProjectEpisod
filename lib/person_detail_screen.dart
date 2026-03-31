import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'api_config.dart';
import 'show_detail_screen.dart';
import 'theme/app_colors.dart'; // YENİ TEMANIZ

class PersonDetailScreen extends StatefulWidget {
  final int personId;
  final String personName;

  const PersonDetailScreen({super.key, required this.personId, required this.personName});

  @override
  State<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<PersonDetailScreen> {
  Map? personDetails;
  List tvCredits = [];
  bool isLoading = true;
  bool isBioExpanded = false;

  @override
  void initState() {
    super.initState();
    _fetchPersonData();
  }

  Future<void> _fetchPersonData() async {
    try {
      // 1. Kişi Detayları (Biyografi, Doğum vb.)
      final detailUrl = Uri.parse('${ApiConfig.baseUrl}/person/${widget.personId}?api_key=${ApiConfig.apiKey}');
      // 2. Oynadığı Diziler
      final creditsUrl = Uri.parse('${ApiConfig.baseUrl}/person/${widget.personId}/tv_credits?api_key=${ApiConfig.apiKey}');

      final responses = await Future.wait([
        http.get(detailUrl),
        http.get(creditsUrl),
      ]);

      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final details = json.decode(responses[0].body);
        final credits = json.decode(responses[1].body)['cast'] as List;

        // Oynadığı dizileri popülerliğe ve bölüm sayısına göre sıralayalım
        credits.sort((a, b) => (b['episode_count'] ?? 0).compareTo(a['episode_count'] ?? 0));

        if (mounted) {
          setState(() {
            personDetails = details;
            // Sadece resimli ve en az 1 bölüm oynadığı dizileri alalım
            tvCredits = credits.where((c) => c['poster_path'] != null && (c['episode_count'] ?? 0) > 0).toList();
            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Person fetch error: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ÖDÜL RADARI HİLESİ: Biyografide ödül kelimeleri geçiyorsa tag oluşturur.
  List<String> _detectAwards(String? bio) {
    if (bio == null || bio.isEmpty) return [];
    List<String> awards = [];
    final text = bio.toLowerCase();
    if (text.contains('emmy')) awards.add('Emmy');
    if (text.contains('golden globe')) awards.add('Golden Globe');
    if (text.contains('oscar') || text.contains('academy award')) awards.add('Oscar');
    if (text.contains('bafta')) awards.add('BAFTA');
    return awards;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator(color: AppColors.accent)),
      );
    }

    final bio = personDetails?['biography'] ?? '';
    final detectedAwards = _detectAwards(bio);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 400,
            pinned: true,
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.personName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  personDetails?['profile_path'] != null
                      ? CachedNetworkImage(
                    imageUrl: "https://image.tmdb.org/t/p/w780${personDetails!['profile_path']}",
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  )
                      : Container(color: AppColors.surface, child: const Icon(Icons.person, size: 100, color: AppColors.textMuted)),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, AppColors.background],
                        stops: [0.5, 1.0],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // İSTATİSTİKLER (Doğum Yeri, Yaş vs)
                  if (personDetails?['birthday'] != null)
                    Text("Born: ${personDetails!['birthday']} ${personDetails?['place_of_birth'] != null ? '(${personDetails!['place_of_birth']})' : ''}",
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),

                  const SizedBox(height: 16),

                  // ÖDÜL RADARI (HATA BURADA ÇÖZÜLDÜ -> ROW YERİNE WRAP KULLANILDI)
                  if (detectedAwards.isNotEmpty) ...[
                    Wrap(
                      spacing: 8, // Yan yana kutular arası boşluk
                      runSpacing: 8, // Alt alta indiklerinde aradaki boşluk
                      children: detectedAwards.map((a) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: AppColors.accentSecondary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.accentSecondary)
                        ),
                        child: Text("🏆 $a Mention", style: const TextStyle(color: AppColors.accentSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                      )).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // BİYOGRAFİ
                  if (bio.isNotEmpty) ...[
                    const Text("ABOUT", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => setState(() => isBioExpanded = !isBioExpanded),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bio,
                            maxLines: isBioExpanded ? null : 4,
                            overflow: isBioExpanded ? TextOverflow.visible : TextOverflow.fade,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.5),
                          ),
                          if (!isBioExpanded && bio.length > 200)
                            const Padding(
                              padding: EdgeInsets.only(top: 4.0),
                              child: Text("Read more...", style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 12)),
                            )
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],

                  // OYNADIĞI DİZİLER VE BÖLÜM SAYILARI
                  if (tvCredits.isNotEmpty) ...[
                    const Text("KNOWN FOR (TV SHOWS)", style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1.2)),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 220,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: tvCredits.length,
                        itemBuilder: (context, index) {
                          final show = tvCredits[index];
                          return GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ShowDetailScreen(show: show))),
                            child: Container(
                              width: 120,
                              margin: const EdgeInsets.only(right: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: "https://image.tmdb.org/t/p/w342${show['poster_path']}",
                                      height: 160, width: 120, fit: BoxFit.cover,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(show['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                                  // KAÇ BÖLÜM OYNADIĞINI BURADA YAZIYORUZ
                                  Text("${show['episode_count']} Episodes", style: const TextStyle(color: AppColors.accentSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                                  Text(show['character'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  ]
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}