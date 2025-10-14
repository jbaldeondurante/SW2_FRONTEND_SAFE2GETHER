// lib/features/reportes/reportes_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/api_client.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_service.dart';
import 'reportes_create.dart';
// Removed unused imports: go_router, env

class ReportesPage extends StatefulWidget {
  final ApiClient api;
  const ReportesPage({super.key, required this.api});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> {
  static const String _base = 'http://127.0.0.1:8000';
  late Future<_PageData> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchAll();
  }

  Future<_PageData> _fetchAll() async {
    final r = await http.get(Uri.parse('$_base/Reportes'));
    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode} al obtener Reportes');
    }
    final List<dynamic> raw = jsonDecode(r.body);
    final reports = raw.map((e) => Report.fromJson(e as Map<String, dynamic>)).toList();
    // Ordenar del más reciente al más antiguo
    reports.sort((a, b) {
      final ta = a.createdAt;
      final tb = b.createdAt;
      if (tb != null && ta != null) return tb.compareTo(ta); // desc
      if (tb != null) return 1; // a sin fecha va después
      if (ta != null) return -1; // b sin fecha va después
      return b.id.compareTo(a.id); // fallback por id desc
    });

    // Traer nombres de usuario (sin duplicados)
    final ids = reports.map((e) => e.userId).toSet();
    final names = <int, String>{};
    await Future.wait(ids.map((id) async {
      try {
        final u = await http.get(Uri.parse('$_base/users/$id'));
        if (u.statusCode == 200) {
          final data = jsonDecode(u.body);
          names[id] = (data is Map && data['user'] != null)
              ? data['user'].toString()
              : 'Usuario $id';
        } else {
          names[id] = 'Usuario $id';
        }
      } catch (_) {
        names[id] = 'Usuario $id';
      }
    }));

    // Traer adjuntos (imagenes) y cruzar por reporte_id
    final adjRes = await http.get(Uri.parse('$_base/Adjunto'));
    final imagenesPorReporte = <int, List<String>>{};
    if (adjRes.statusCode == 200) {
      final adjuntos = jsonDecode(adjRes.body) as List<dynamic>;
      for (final adj in adjuntos) {
        if (adj is Map<String, dynamic> && adj['reporte_id'] != null && adj['url'] != null) {
          final tipo = adj['tipo']?.toString().toLowerCase();
          final url = (adj['url'] as String).toString();
          // Aceptar varios tipos comunes y, si no hay tipo, inferir por extensión de la URL
          const tiposValidos = {'foto','imagen','image','img','picture','photo'};
          final lowerUrl = url.toLowerCase();
          const exts = ['.jpg','.jpeg','.png','.gif','.webp','.bmp','.svg','.heic','.heif'];
          final looksLikeImage = exts.any((e) => lowerUrl.contains(e));

          if ((tipo != null && tiposValidos.contains(tipo)) || (tipo == null || tipo.isEmpty) && looksLikeImage) {
            final rid = adj['reporte_id'] as int;
            imagenesPorReporte.putIfAbsent(rid, () => []).add(url);
          }
        }
      }
    }

    return _PageData(reports: reports, userNames: names, imagenesPorReporte: imagenesPorReporte);
  }

  Future<void> _refresh() async {
    setState(() => _future = _fetchAll());
    await _future;
  }

  // ⬇️ IMPORTANTE: este build DEBE existir, con esta firma exacta
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E2D52),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08192D),
        foregroundColor: Colors.white,
        title: SizedBox(
          height: 36,
          child: Image.asset(
            'assets/logo.png',
            fit: BoxFit.contain,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Mapa de calor (Lima)',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => context.push('/mapa'),
          ),
          IconButton(
            tooltip: 'Nuevo reporte',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () async {
              await showDialog(
                context: context,
                builder: (ctx) {
                  return AlertDialog(
                    backgroundColor: Colors.white,
                    contentPadding: const EdgeInsets.all(16),
                    content: SizedBox(
                      width: 420,
                      child: ReportesCreateForm(
                        onSuccess: () {
                          // refrescar al cerrar
                          _refresh();
                        },
                      ),
                    ),
                  );
                },
              );
            },
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              try {
                await GetIt.instance<SupabaseService>().signOut();
                if (context.mounted) context.go('/login');
              } catch (_) {}
            },
          ),
        ],
      ),
      body: FutureBuilder<_PageData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: _ErrorView(
                  message: snap.error.toString(),
                  onRetry: _refresh,
                ),
              ),
            );
          }
          final data = snap.data!;
          if (data.reports.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: [
                  const SizedBox(height: 48),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          children: const [
                            SizedBox(height: 200),
                            Center(child: Text('No hay reportes')),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: data.reports.length,
              itemBuilder: (context, i) {
                final r = data.reports[i];
                final user = data.userNames[r.userId] ?? 'Usuario ${r.userId}';
                final imagenes = data.imagenesPorReporte[r.id];
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: _ReportCard(report: r, userName: user, imagenes: imagenes),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class Report {
  final int userId;
  final String titulo;
  final String descripcion;
  final String categoria;
  final double? lat;
  final double? lon;
  final String direccion;
  final String estado;
  final double? veracidad;
  final int id;
  final DateTime? createdAt;

  Report({
    required this.userId,
    required this.titulo,
    required this.descripcion,
    required this.categoria,
    required this.lat,
    required this.lon,
    required this.direccion,
    required this.estado,
    required this.veracidad,
    required this.id,
    required this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> j) {
    double? asD(v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    DateTime? asT(v) {
      if (v == null) return null;
      try { return DateTime.parse('$v'); } catch (_) { return null; }
    }

    return Report(
      userId: j['user_id'] as int,
      titulo: '${j['titulo'] ?? ''}',
      descripcion: '${j['descripcion'] ?? ''}',
      categoria: '${j['categoria'] ?? ''}',
      lat: asD(j['lat']),
      lon: asD(j['lon']),
      direccion: '${j['direccion'] ?? ''}',
      estado: '${j['estado'] ?? ''}',
      veracidad: asD(j['veracidad_porcentaje']),
      id: j['id'] as int,
      createdAt: asT(j['created_at']),
    );
  }
}

class _PageData {
  final List<Report> reports;
  final Map<int, String> userNames;
  final Map<int, List<String>> imagenesPorReporte; // reporte_id -> lista de urls
  _PageData({required this.reports, required this.userNames, required this.imagenesPorReporte});
}

class _ReportCard extends StatelessWidget {
  final Report report;
  final String userName;
  final List<String>? imagenes;
  const _ReportCard({Key? key, required this.report, required this.userName, this.imagenes}) : super(key: key);

  Color _estadoColor(String s) {
    switch (s.toUpperCase()) {
      case 'ACTIVO': return Colors.orange;
      case 'RESUELTO':
      case 'CERRADO': return Colors.green;
      case 'EN PROCESO': return Colors.blueGrey;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = report.veracidad;
    final vTxt = v == null ? '—' : '${v.toStringAsFixed(0)}%';
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título + estado
            Row(
              children: [
                Expanded(
                  child: Text(
                    report.titulo.isEmpty ? 'Reporte #${report.id}' : report.titulo,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                  label: Text(report.estado),
                  backgroundColor: _estadoColor(report.estado).withOpacity(0.12),
                  side: BorderSide(color: _estadoColor(report.estado).withOpacity(0.4)),
                  labelStyle: TextStyle(
                    color: _estadoColor(report.estado),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.person, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(userName, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              report.descripcion.trim().isEmpty ? 'Sin descripción' : report.descripcion.trim(),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            if (imagenes != null && imagenes!.isNotEmpty) ...[
              SizedBox(
                height: 180,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: imagenes!.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, idx) {
                    final url = imagenes![idx];
                    return GestureDetector(
                      onTap: () => _openImageViewer(ctx, imagenes!, startIndex: idx),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          url,
                          height: 180,
                          width: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => Container(
                            height: 180,
                            width: 220,
                            color: Colors.grey[200],
                            child: const Center(child: Icon(Icons.broken_image, size: 40)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    report.direccion.isEmpty ? 'Dirección no especificada' : report.direccion,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.verified, size: 18),
                const SizedBox(width: 6),
                Text('Veracidad: $vTxt'),
              ],
            ),
            if (v != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(value: (v.clamp(0, 100)) / 100.0, minHeight: 8),
              ),
            ],
            if (report.createdAt != null) ...[
              const SizedBox(height: 8),
              Text('Creado el: ${report.createdAt!.toLocal()}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[700])),
            ],
          ],
        ),
      ),
    );
  }
}

void _openImageViewer(BuildContext context, List<String> urls, {int startIndex = 0}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImageViewer(urls: urls, initialIndex: startIndex),
    ),
  );
}

class _ImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _ImageViewer({Key? key, required this.urls, this.initialIndex = 0}) : super(key: key);

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${widget.initialIndex + 1}/${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        itemBuilder: (_, i) {
          final url = widget.urls[i];
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white70, size: 64),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({Key? key, required this.message, required this.onRetry}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            const Text('Error cargando datos', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
