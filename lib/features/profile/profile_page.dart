// lib/features/profile/profile_page.dart
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../core/api_client.dart';
import '../../core/supabase_service.dart';

class ProfilePage extends StatefulWidget {
  final ApiClient api;
  const ProfilePage({super.key, required this.api});

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
    final id = svc.backendUserId;
    final username = svc.backendUsername ?? 'Usuario';
    if (id == null) {
      throw Exception('No hay usuario del backend en sesión.');
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
        title: const Text('Mi perfil'),
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
                if (data.reports.isEmpty)
                  const _Empty()
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

class _Header extends StatelessWidget {
  final String username;
  final int userId;
  const _Header({required this.username, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF0C2542),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            const CircleAvatar(radius: 26, child: Icon(Icons.person, size: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: $userId',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
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
  const _Empty();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: const [
          Icon(Icons.inbox_outlined, color: Colors.white70, size: 48),
          SizedBox(height: 8),
          Text(
            'No has creado reportes aún',
            style: TextStyle(color: Colors.white70),
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
