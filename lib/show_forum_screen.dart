import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShowForumScreen extends StatefulWidget {
  final int showId;
  final String showName;

  const ShowForumScreen({super.key, required this.showId, required this.showName});

  @override
  State<ShowForumScreen> createState() => _ShowForumScreenState();
}

class _ShowForumScreenState extends State<ShowForumScreen> {
  final _supabase = Supabase.instance.client;
  final _commentController = TextEditingController();
  final _focusNode = FocusNode();

  List comments = [];
  List userLikes = [];
  Map? replyingTo;

  // YENİ: Hangi yorumların yanıtları açık? (Açık olanların ID'sini tutar)
  final Set<int> _expandedReplies = {};

  // YENİ: Sıralama seçeneği
  String _currentSort = 'Newest';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final user = _supabase.auth.currentUser;
      final results = await Future.wait<dynamic>([
        // Tüm yorumları çeker (Sıralamayı Flutter tarafında yapacağız)
        _supabase.from('comments').select('*, profiles(username), comment_likes(count)').eq('show_id', widget.showId).isFilter('season_number', null),
        if (user != null) _supabase.from('comment_likes').select('comment_id').eq('user_id', user.id) else Future.value([]),
      ]);

      if (mounted) {
        setState(() {
          comments = results[0] as List;
          userLikes = (results[1] as List).map((l) => l['comment_id']).toList();
        });
      }
    } catch (e) { debugPrint("Forum error: $e"); }
  }

  // Yardımcı fonksiyonlar: Beğeni ve Yanıt sayılarını güvenli çeker
  int _getLikes(Map c) => c['comment_likes'] != null && c['comment_likes'].isNotEmpty ? (c['comment_likes'][0]['count'] ?? 0) : 0;
  int _getReplyCount(Map c) => comments.where((r) => r['parent_id'] == c['id']).length;

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final user = _supabase.auth.currentUser;
    _commentController.clear();

    // Eğer birine yanıt veriyorsak, o yorumun reply'larını otomatik aç ki yazdığını görsün
    if (replyingTo != null) {
      _expandedReplies.add(replyingTo!['id']);
    }

    await _supabase.from('comments').insert({
      'user_id': user!.id,
      'show_id': widget.showId,
      'content': text,
      'parent_id': replyingTo?['id'],
    });

    setState(() => replyingTo = null);
    _focusNode.unfocus();
    _fetchData();
  }

  Future<void> _toggleLike(int commentId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    if (userLikes.contains(commentId)) {
      await _supabase.from('comment_likes').delete().eq('user_id', user.id).eq('comment_id', commentId);
    } else {
      await _supabase.from('comment_likes').insert({'user_id': user.id, 'comment_id': commentId});
    }
    _fetchData();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Sadece Ana Yorumları (Parent) al
    List mainComments = comments.where((c) => c['parent_id'] == null).toList();

    // 2. Sıralama Mantığı (Flutter üzerinde dinamik sıralama)
    mainComments.sort((a, b) {
      if (_currentSort == 'Top Liked') {
        return _getLikes(b).compareTo(_getLikes(a)); // En çok beğenilen en üste
      } else if (_currentSort == 'Most Discussed') {
        return _getReplyCount(b).compareTo(_getReplyCount(a)); // En çok yanıt alan en üste
      } else {
        // Newest (En Yeni)
        return DateTime.parse(b['created_at']).compareTo(DateTime.parse(a['created_at']));
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF14181C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14181C),
        title: Text("${widget.showName} Forum", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: () => Navigator.pop(context)),
        actions: [
          // YENİ: SIRALAMA BUTONU
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort, color: Colors.white, size: 22),
            color: const Color(0xFF2C3440),
            onSelected: (value) {
              if (value == 'Top Authors') {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Follower sorting requires the Follow system! Coming next.")));
                return;
              }
              setState(() => _currentSort = value);
            },
            itemBuilder: (context) => [
              _buildPopupItem('Newest', Icons.access_time),
              _buildPopupItem('Top Liked', Icons.thumb_up_alt_outlined),
              _buildPopupItem('Most Discussed', Icons.forum_outlined),
              _buildPopupItem('Top Authors', Icons.people_outline), // Takip sistemi gelince çalışacak
            ],
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchData,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: mainComments.length,
                itemBuilder: (context, i) {
                  final parent = mainComments[i];
                  // Bu ana yoruma ait yanıtları eskiden yeniye (Thread mantığı) sıralayarak bul
                  final replies = comments.where((c) => c['parent_id'] == parent['id']).toList()
                    ..sort((a, b) => DateTime.parse(a['created_at']).compareTo(DateTime.parse(b['created_at'])));

                  final bool isExpanded = _expandedReplies.contains(parent['id']);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ANA YORUM
                      _buildCommentTile(parent, isReply: false),

                      // YOUTUBE TARZI YANITLARI GÖSTER/GİZLE BUTONU
                      if (replies.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 44, top: 4, bottom: 8),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                if (isExpanded) _expandedReplies.remove(parent['id']);
                                else _expandedReplies.add(parent['id']);
                              });
                            },
                            child: Row(
                              children: [
                                Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: const Color(0xFF00E054), size: 18),
                                const SizedBox(width: 4),
                                Text(isExpanded ? "Hide replies" : "View ${replies.length} replies", style: const TextStyle(color: Color(0xFF00E054), fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),

                      // YANITLAR (Sadece isExpanded true ise renderlanır)
                      if (isExpanded)
                        ...replies.map((r) => Padding(
                            padding: const EdgeInsets.only(left: 44, bottom: 8),
                            child: _buildCommentTile(r, isReply: true)
                        )),

                      const Divider(color: Colors.white10, height: 32),
                    ],
                  );
                },
              ),
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, IconData icon) {
    return PopupMenuItem(
      value: value,
      child: Row(children: [
        Icon(icon, color: _currentSort == value ? const Color(0xFF00E054) : Colors.white70, size: 18),
        const SizedBox(width: 12),
        Text(value, style: TextStyle(color: _currentSort == value ? const Color(0xFF00E054) : Colors.white, fontSize: 14, fontWeight: _currentSort == value ? FontWeight.bold : FontWeight.normal)),
      ]),
    );
  }

  Widget _buildCommentTile(Map c, {required bool isReply}) {
    final bool isLiked = userLikes.contains(c['id']);
    final int likeCount = _getLikes(c);

    // Ne zaman atıldı hesabı (Örn: 2h ago)
    final Duration diff = DateTime.now().difference(DateTime.parse(c['created_at']).toLocal());
    String timeAgo = diff.inDays > 0 ? "${diff.inDays}d" : diff.inHours > 0 ? "${diff.inHours}h" : diff.inMinutes > 0 ? "${diff.inMinutes}m" : "now";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(radius: isReply ? 12 : 16, backgroundColor: Colors.white10, child: Text(c['profiles']['username'][0].toUpperCase(), style: const TextStyle(color: Color(0xFF00E054), fontSize: 10))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(c['profiles']['username'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 8),
                    Text(timeAgo, style: const TextStyle(color: Colors.white30, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(c['content'], style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _toggleLike(c['id']),
                      child: Row(children: [
                        Icon(isLiked ? Icons.thumb_up : Icons.thumb_up_outlined, size: 14, color: isLiked ? const Color(0xFF00E054) : Colors.grey),
                        const SizedBox(width: 4),
                        Text(likeCount > 0 ? "$likeCount" : "", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      ]),
                    ),
                    const SizedBox(width: 24),
                    if (!isReply)
                      GestureDetector(
                        onTap: () { setState(() => replyingTo = c); _focusNode.requestFocus(); },
                        child: const Text("Reply", style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 10, left: 16, right: 16, top: 10),
      decoration: const BoxDecoration(color: Color(0xFF1E2329), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      child: Column(
        children: [
          if (replyingTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(children: [
                Text("Replying to ${replyingTo!['profiles']['username']}", style: const TextStyle(color: Color(0xFF00E054), fontSize: 11)),
                const Spacer(),
                IconButton(onPressed: () => setState(() => replyingTo = null), icon: const Icon(Icons.close, size: 16, color: Colors.white24), padding: EdgeInsets.zero, constraints: const BoxConstraints())
              ]),
            ),
          Row(children: [
            Expanded(child: TextField(controller: _commentController, focusNode: _focusNode, style: const TextStyle(color: Colors.white, fontSize: 14), decoration: const InputDecoration(hintText: "Add a comment...", hintStyle: TextStyle(color: Colors.white24), border: InputBorder.none))),
            IconButton(onPressed: _postComment, icon: const Icon(Icons.send, color: Color(0xFF00E054))),
          ]),
        ],
      ),
    );
  }
}