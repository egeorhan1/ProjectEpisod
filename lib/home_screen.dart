import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'api_config.dart';
import 'show_detail_screen.dart';
import 'theme/app_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List trendingShows = []; // Yeni çıkan / Gündemdeki diziler
  List airingShows = []; // Yeni sezonu/bölümü yayınlanan diziler
  List popularShows = []; // Genel popüler diziler

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAllShows();
  }

  // TMDB'den aynı anda 3 farklı listeyi çeker
  Future<void> _fetchAllShows() async {
    try {
      final results = await Future.wait([
        http.get(
          Uri.parse(
            '${ApiConfig.baseUrl}/trending/tv/week?api_key=${ApiConfig.apiKey}&language=en-US',
          ),
        ),
        http.get(
          Uri.parse(
            '${ApiConfig.baseUrl}/tv/on_the_air?api_key=${ApiConfig.apiKey}&language=en-US',
          ),
        ),
        http.get(
          Uri.parse(
            '${ApiConfig.baseUrl}/tv/popular?api_key=${ApiConfig.apiKey}&language=en-US',
          ),
        ),
      ]);

      if (mounted) {
        setState(() {
          if (results[0].statusCode == 200)
            trendingShows = json.decode(results[0].body)['results'];
          if (results[1].statusCode == 200)
            airingShows = json.decode(results[1].body)['results'];
          if (results[2].statusCode == 200)
            popularShows = json.decode(results[2].body)['results'];
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Veri çekme hatası: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        flexibleSpace: Container(
          color: AppColors.background,
        ), // Sabit siyah üst bar
        title: const Text(
          "Episod",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontSize: 22,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : RefreshIndicator(
              onRefresh: _fetchAllShows,
              color: AppColors.accent,
              backgroundColor: AppColors.background,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. SATIR: Yeni Çıkanlar (Gündemdekiler)
                      _buildNetflixRow(
                        "TRENDING NOW",
                        trendingShows,
                        "trending",
                      ),
                      const SizedBox(height: 24),

                      // 2. SATIR: Yeni Sezonu/Bölümü Gelenler
                      _buildNetflixRow(
                        "NEW EPISODES AIRING",
                        airingShows,
                        "airing",
                      ),
                      const SizedBox(height: 24),

                      // 3. SATIR: Klasik Popülerler
                      _buildNetflixRow(
                        "POPULAR SHOWS",
                        popularShows,
                        "popular",
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  // --- NETFLIX TARZI YATAY KAYDIRMA WIDGET'I ---
  Widget _buildNetflixRow(String title, List shows, String heroPrefix) {
    if (shows.isEmpty)
      return const SizedBox.shrink(); // Veri yoksa boşluk bırakma

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200, // Posterlerin yüksekliği
          child: ListView.builder(
            scrollDirection: Axis.horizontal, // Sağa doğru kaydırma sihri
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            itemCount: shows.length,
            itemBuilder: (context, index) {
              final show = shows[index];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ShowDetailScreen(show: show),
                    ),
                  );
                },
                child: Container(
                  width: 130, // Posterin genişliği
                  margin: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Hero(
                    // Aynı dizi birden fazla listede olursa çökmemesi için heroTag'e prefix ekliyoruz
                    tag: '${heroPrefix}_${show['id']}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: show['poster_path'] != null
                          ? CachedNetworkImage(
                              imageUrl:
                                  "https://image.tmdb.org/t/p/w342${show['poster_path']}",
                              fit: BoxFit.cover,
                              placeholder: (context, url) =>
                                  Container(color: AppColors.divider),
                              errorWidget: (context, url, error) =>
                                  const Icon(Icons.error),
                            )
                          : Container(
                              color: AppColors.elevated,
                              child: const Icon(
                                Icons.tv,
                                color: AppColors.textMuted,
                              ),
                            ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
