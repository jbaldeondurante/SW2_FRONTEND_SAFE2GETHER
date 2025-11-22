// lib/features/profile/followers_page.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/responsive_utils.dart';

class _UserInfo {
  final int id;
  final String username;
  final bool notificarReportes;
  final int? relationId; // ID de la relación en la tabla Seguidores

  _UserInfo({
    required this.id, 
    required this.username,
    this.notificarReportes = true,
    this.relationId,
  });
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
          
          final relationId = rel['id'] as int?;
          final notificarReportes = rel['notificar_reportes'] as bool? ?? true;
          
          if (targetUserId != null) {
            try {
              final userRes = await widget.api.getJson('/users/$targetUserId');
              if ((userRes['status'] as int? ?? 200) < 400) {
                final userData = userRes['data'] ?? userRes;
                if (userData is Map) {
                  users.add(_UserInfo(
                    id: targetUserId,
                    username: userData['user']?.toString() ?? 'Usuario $targetUserId',
                    notificarReportes: notificarReportes,
                    relationId: relationId,
                  ));
                }
              } else {
                users.add(_UserInfo(
                  id: targetUserId,
                  username: 'Usuario $targetUserId',
                  notificarReportes: notificarReportes,
                  relationId: relationId,
                ));
              }
            } catch (_) {
              users.add(_UserInfo(
                id: targetUserId,
                username: 'Usuario $targetUserId',
                notificarReportes: notificarReportes,
                relationId: relationId,
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

          final padding = ResponsiveHelper.getPadding(context);
          final spacing = ResponsiveHelper.getVerticalSpacing(context) * 0.75;
          return ListView.builder(
            padding: padding,
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return Card(
                color: const Color(0xFF0C2542),
                margin: EdgeInsets.only(bottom: spacing),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person),
                  ),
                  title: Text(
                    user.username,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: widget.showFollowers
                      ? Text(
                          'ID: ${user.id}',
                          style: const TextStyle(color: Colors.white70),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ID: ${user.id}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  user.notificarReportes ? Icons.notifications_active : Icons.notifications_off,
                                  size: 14,
                                  color: user.notificarReportes ? Colors.green : Colors.grey,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  user.notificarReportes ? 'Notificaciones activas' : 'Notificaciones desactivadas',
                                  style: TextStyle(
                                    color: user.notificarReportes ? Colors.green : Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                  trailing: widget.showFollowers
                      ? const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white70,
                          size: 16,
                        )
                      : Switch(
                          value: user.notificarReportes,
                          onChanged: (value) async {
                            try {
                              // Llamar al endpoint para actualizar preferencias
                              await widget.api.updateNotificationPreference(
                                seguidorId: widget.userId,
                                seguidoId: user.id,
                                notificar: value,
                              );
                              
                              // Recargar la lista
                              setState(() {
                                _future = _loadUsers();
                              });
                              
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      value
                                          ? 'Notificaciones activadas para ${user.username}'
                                          : 'Notificaciones desactivadas para ${user.username}',
                                    ),
                                    backgroundColor: value ? Colors.green : Colors.grey,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error al actualizar preferencias: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          activeColor: Colors.green,
                        ),
                  onTap: widget.showFollowers
                      ? () {
                          context.push('/profile/${user.id}');
                        }
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
