// lib/features/profile/followers_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';

class _UserInfo {
  final int id;
  final String username;

  _UserInfo({required this.id, required this.username});
}

class FollowersPage extends StatefulWidget {
  final ApiClient api;
  final int userId;
  final String username;
  final bool showFollowers; // true = seguidores, false = seguidos

  const FollowersPage({
    super.key,
    required this.api,
    required this.userId,
    required this.username,
    this.showFollowers = true,
  });

  @override
  State<FollowersPage> createState() => _FollowersPageState();
}

class _FollowersPageState extends State<FollowersPage> {
  late Future<List<_UserInfo>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadUsers();
  }

  Future<List<_UserInfo>> _loadUsers() async {
    try {
      final List<dynamic> relations;
      
      if (widget.showFollowers) {
        relations = await widget.api.getFollowers(widget.userId);
      } else {
        relations = await widget.api.getFollowing(widget.userId);
      }

      final users = <_UserInfo>[];
      
      for (final rel in relations) {
        if (rel is Map<String, dynamic>) {
          final targetUserId = widget.showFollowers 
              ? rel['seguidor_id'] as int?
              : rel['seguido_id'] as int?;
          
          if (targetUserId != null) {
            try {
              final userRes = await widget.api.getJson('/users/$targetUserId');
              if ((userRes['status'] as int? ?? 200) < 400) {
                final userData = userRes['data'] ?? userRes;
                if (userData is Map) {
                  users.add(_UserInfo(
                    id: targetUserId,
                    username: userData['user']?.toString() ?? 'Usuario $targetUserId',
                  ));
                }
              } else {
                users.add(_UserInfo(
                  id: targetUserId,
                  username: 'Usuario $targetUserId',
                ));
              }
            } catch (_) {
              users.add(_UserInfo(
                id: targetUserId,
                username: 'Usuario $targetUserId',
              ));
            }
          }
        }
      }

      return users;
    } catch (e) {
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E2D52),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08192D),
        foregroundColor: Colors.white,
        title: Text(widget.showFollowers 
            ? '${widget.username} - Seguidores'
            : '${widget.username} - Seguidos'),
        centerTitle: true,
      ),
      body: FutureBuilder<List<_UserInfo>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final users = snapshot.data ?? [];

          if (users.isEmpty) {
            return Center(
              child: Text(
                widget.showFollowers 
                    ? 'No hay seguidores aún'
                    : 'No sigue a ningún usuario',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return Card(
                color: const Color(0xFF0C2542),
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person),
                  ),
                  title: Text(
                    user.username,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    'ID: ${user.id}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white70,
                    size: 16,
                  ),
                  onTap: () {
                    context.push('/profile/${user.id}');
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
