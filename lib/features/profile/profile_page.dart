// lib/features/profile/profile_page.dart
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/api_client.dart';
import '../../core/supabase_service.dart';

class ProfilePage extends StatefulWidget {
  final ApiClient api;
  final int? userId; // si null, usa usuario en sesión
  const ProfilePage({super.key, required this.api, this.userId});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late Future<_ProfileData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ProfileData> _load() async {
    final svc = GetIt.instance<SupabaseService>();
    final id = widget.userId ?? svc.backendUserId;
    String username = svc.backendUsername ?? 'Usuario';
    if (id == null) {
      throw Exception('No hay usuario del backend en sesión.');
    }
    // Si estamos viendo otro usuario, intenta obtener su nombre
    if (widget.userId != null && widget.userId != svc.backendUserId) {
      try {
        final res = await widget.api.getJson('/users/$id');
        if ((res['status'] as int? ?? 200) < 400) {
          final data = res['data'] ?? res;
          if (data is Map && data['user'] != null) {
            username = data['user'].toString();
          }
        }
      } catch (_) {}
    }
    final r = await widget.api.getJson('/Reportes/user/$id');
    final status = r['status'] as int? ?? 200;
    if (status >= 400) {
      throw Exception('HTTP $status al obtener reportes del usuario');
    }
    final list =
        (r['data'] as List?) ?? (r['results'] as List?) ?? r['items'] as List?;
    final reports = <_MyReport>[];
    if (list != null) {
      for (final it in list) {
        if (it is Map) {
          reports.add(_MyReport.fromJson(Map<String, dynamic>.from(it)));
        }
      }
    }
    // Orden más reciente primero cuando haya fecha
    reports.sort((a, b) {
      if (a.createdAt != null && b.createdAt != null) {
        return b.createdAt!.compareTo(a.createdAt!);
      }
      return b.id.compareTo(a.id);
    });
    return _ProfileData(username: username, userId: id, reports: reports);
  }

  Future<void> _refresh() async {
    setState(() => _future = _load());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E2D52),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08192D),
        foregroundColor: Colors.white,
  title: const Text('Perfil'),
        centerTitle: true,
      ),
      body: FutureBuilder<_ProfileData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error: ${snap.error}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final data = snap.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: _Header(
                      username: data.username,
                      userId: data.userId,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: _FollowStats(
                      username: data.username,
                      userId: data.userId,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (data.reports.isEmpty)
                  _Empty(isSelf: GetIt.instance<SupabaseService>().backendUserId == data.userId)
                else
                  ...data.reports.map(
                    (r) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: _ReportTile(report: r),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatefulWidget {
  final String username;
  final int userId;
  const _Header({required this.username, required this.userId});

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  bool _isFollowing = false;
  bool _loading = true;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _checkFollowingStatus();
  }

  Future<void> _checkFollowingStatus() async {
    final svc = GetIt.instance<SupabaseService>();
    final currentUserId = svc.backendUserId;
    
    // Si es el propio perfil, no mostramos botón de seguir
    if (currentUserId == null || currentUserId == widget.userId) {
      setState(() => _loading = false);
      return;
    }

    try {
      final api = GetIt.instance<ApiClient>();
      final isFollowing = await api.isFollowing(
        seguidorId: currentUserId,
        seguidoId: widget.userId,
      );
      if (mounted) {
        setState(() {
          _isFollowing = isFollowing;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _toggleFollow() async {
    final svc = GetIt.instance<SupabaseService>();
    final currentUserId = svc.backendUserId;
    
    if (currentUserId == null) return;

    setState(() => _actionLoading = true);

    try {
      final api = GetIt.instance<ApiClient>();
      
      if (_isFollowing) {
        await api.unfollowUser(
          seguidorId: currentUserId,
          seguidoId: widget.userId,
        );
        if (mounted) {
          setState(() => _isFollowing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Has dejado de seguir a este usuario')),
          );
        }
      } else {
        await api.followUser(
          seguidorId: currentUserId,
          seguidoId: widget.userId,
        );
        if (mounted) {
          setState(() => _isFollowing = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ahora sigues a este usuario')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = GetIt.instance<SupabaseService>();
    final currentUserId = svc.backendUserId;
    final isSelf = currentUserId == widget.userId;

    return Card(
      color: const Color(0xFF0C2542),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: const Color(0xFF1E88E5),
                  child: Text(
                    widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'U',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.username,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@user${widget.userId}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isSelf && !_loading)
                  _actionLoading
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : ElevatedButton(
                          onPressed: _toggleFollow,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isFollowing ? Colors.transparent : const Color(0xFF1E88E5),
                            foregroundColor: Colors.white,
                            side: _isFollowing ? const BorderSide(color: Colors.white54) : null,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            _isFollowing ? 'Siguiendo' : 'Seguir',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowStats extends StatefulWidget {
  final String username;
  final int userId;
  const _FollowStats({required this.username, required this.userId});

  @override
  State<_FollowStats> createState() => _FollowStatsState();
}

class _FollowStatsState extends State<_FollowStats> {
  int _followersCount = 0;
  int _followingCount = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final api = GetIt.instance<ApiClient>();
      final followers = await api.getFollowers(widget.userId);
      final following = await api.getFollowing(widget.userId);
      
      if (mounted) {
        setState(() {
          _followersCount = followers.length;
          _followingCount = following.length;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }

    return Card(
      color: const Color(0xFF0C2542),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
        child: Row(
          children: [
            _StatButton(
              label: 'Seguidores',
              count: _followersCount,
              onTap: () {},
            ),
            const SizedBox(width: 20),
            _StatButton(
              label: 'Siguiendo',
              count: _followingCount,
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}

class _StatButton extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback onTap;

  const _StatButton({
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
        child: Row(
          children: [
            Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final _MyReport report;
  const _ReportTile({required this.report});

  @override
  Widget build(BuildContext context) {
    String? dateStr;
    if (report.createdAt != null) {
      final d = report.createdAt!.toLocal();
      String two(int v) => v.toString().padLeft(2, '0');
      dateStr =
          '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
    }
    return Card(
      color: const Color(0xFF0C2542),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey.shade700,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    report.categoria ?? '-',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const Spacer(),
                if (dateStr != null)
                  Text(
                    dateStr,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              report.titulo,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (report.descripcion != null &&
                report.descripcion!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                report.descripcion!,
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final bool isSelf;
  const _Empty({this.isSelf = true});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, color: Colors.white70, size: 48),
          const SizedBox(height: 8),
          Text(
            isSelf ? 'No has creado reportes aún' : 'Este usuario no tiene reportes',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _MyReport {
  final int id;
  final String titulo;
  final String? descripcion;
  final String? categoria;
  final DateTime? createdAt;

  _MyReport({
    required this.id,
    required this.titulo,
    this.descripcion,
    this.categoria,
    this.createdAt,
  });

  factory _MyReport.fromJson(Map<String, dynamic> j) {
    DateTime? asT(v) {
      try {
        if (v == null) return null;
        return DateTime.parse('$v');
      } catch (_) {
        return null;
      }
    }

    return _MyReport(
      id: (j['id'] as num?)?.toInt() ?? 0,
      titulo: '${j['titulo'] ?? ''}',
      descripcion: (j['descripcion'] ?? j['descripción'])?.toString(),
      categoria: (j['categoria'] ?? j['categoría'])?.toString(),
      createdAt: asT(j['created_at']),
    );
  }
}

class _ProfileData {
  final String username;
  final int userId;
  final List<_MyReport> reports;
  _ProfileData({
    required this.username,
    required this.userId,
    required this.reports,
  });
}
