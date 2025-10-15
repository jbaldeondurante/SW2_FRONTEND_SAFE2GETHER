// lib/features/reportes/reportes_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/api_client.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase_service.dart';
import 'reportes_create.dart';
import '../../core/ui.dart';
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
    final currentUserId = GetIt.instance<SupabaseService>().backendUserId;
    final r = await http.get(Uri.parse('$_base/Reportes'));
    if (r.statusCode != 200) {
      throw Exception('HTTP ${r.statusCode} al obtener Reportes');
    }
    final List<dynamic> raw = jsonDecode(r.body);
    final reports = raw
        .map((e) => Report.fromJson(e as Map<String, dynamic>))
        .toList();
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
    await Future.wait(
      ids.map((id) async {
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
      }),
    );

    // Traer adjuntos (imagenes) y cruzar por reporte_id
    final adjRes = await http.get(Uri.parse('$_base/Adjunto'));
    final imagenesPorReporte = <int, List<String>>{};
    if (adjRes.statusCode == 200) {
      final adjuntos = jsonDecode(adjRes.body) as List<dynamic>;
      for (final adj in adjuntos) {
        if (adj is Map<String, dynamic> &&
            adj['reporte_id'] != null &&
            adj['url'] != null) {
          final tipo = adj['tipo']?.toString().toLowerCase();
          final url = (adj['url'] as String).toString();
          // Aceptar varios tipos comunes y, si no hay tipo, inferir por extensión de la URL
          const tiposValidos = {
            'foto',
            'imagen',
            'image',
            'img',
            'picture',
            'photo',
          };
          final lowerUrl = url.toLowerCase();
          const exts = [
            '.jpg',
            '.jpeg',
            '.png',
            '.gif',
            '.webp',
            '.bmp',
            '.svg',
            '.heic',
            '.heif',
          ];
          final looksLikeImage = exts.any((e) => lowerUrl.contains(e));

          if ((tipo != null && tiposValidos.contains(tipo)) ||
              (tipo == null || tipo.isEmpty) && looksLikeImage) {
            final rid = adj['reporte_id'] as int;
            imagenesPorReporte.putIfAbsent(rid, () => []).add(url);
          }
        }
      }
    }

    // Traer reacciones del usuario (si está logueado en backend)
    final userReactions = <int, _UserReaction>{};
    if (currentUserId != null) {
      try {
        final rr = await http.get(
          Uri.parse('$_base/Reacciones/user/$currentUserId'),
        );
        if (rr.statusCode == 200) {
          final list = jsonDecode(rr.body) as List<dynamic>;
          for (final it in list) {
            if (it is Map<String, dynamic>) {
              final rid = it['reporte_id'] as int?;
              final id = it['id'] as int?;
              final tipo = (it['tipo'] as String?)?.toLowerCase();
              if (rid != null &&
                  id != null &&
                  (tipo == 'upvote' || tipo == 'downvote')) {
                userReactions[rid] = _UserReaction(id: id, tipo: tipo!);
              }
            }
          }
        }
      } catch (_) {}
    }

    return _PageData(
      reports: reports,
      userNames: names,
      imagenesPorReporte: imagenesPorReporte,
      userReactions: userReactions,
      currentUserId: currentUserId,
    );
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
          child: Image.asset('assets/logo.png', fit: BoxFit.contain),
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
              final result = await showDialog<bool>(
                context: context,
                builder: (ctx) {
                  return AlertDialog(
                    backgroundColor: Colors.white,
                    contentPadding: const EdgeInsets.all(16),
                    content: SizedBox(width: 420, child: ReportesCreateForm()),
                  );
                },
              );
              if (result == true) {
                _refresh();
              }
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
                            SizedBox(height: 120),
                            Icon(
                              Icons.inbox_outlined,
                              color: Colors.white70,
                              size: 48,
                            ),
                            SizedBox(height: 12),
                            Center(
                              child: Text(
                                'No hay reportes aún',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                            SizedBox(height: 8),
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
                final reaction = data.userReactions[r.id];
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: _ReportCard(
                        report: r,
                        userName: user,
                        imagenes: imagenes,
                        userReaction: reaction,
                        currentUserId: data.currentUserId,
                      ),
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
  final int upvotes;
  final int downvotes;
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
    required this.upvotes,
    required this.downvotes,
    required this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> j) {
    double? asD(v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    DateTime? asT(v) {
      if (v == null) return null;
      try {
        return DateTime.parse('$v');
      } catch (_) {
        return null;
      }
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
      upvotes: (j['cantidad_upvotes'] as int?) ?? 0,
      downvotes: (j['cantidad_downvotes'] as int?) ?? 0,
      createdAt: asT(j['created_at']),
    );
  }
}

class _PageData {
  final List<Report> reports;
  final Map<int, String> userNames;
  final Map<int, List<String>>
  imagenesPorReporte; // reporte_id -> lista de urls
  final Map<int, _UserReaction>
  userReactions; // reporte_id -> reaccion del usuario
  final int? currentUserId;
  _PageData({
    required this.reports,
    required this.userNames,
    required this.imagenesPorReporte,
    required this.userReactions,
    required this.currentUserId,
  });
}

class _UserReaction {
  final int id;
  final String tipo; // 'upvote' | 'downvote'
  const _UserReaction({required this.id, required this.tipo});
}

class _ReportCard extends StatefulWidget {
  final Report report;
  final String userName;
  final List<String>? imagenes;
  final _UserReaction? userReaction;
  final int? currentUserId;
  const _ReportCard({
    Key? key,
    required this.report,
    required this.userName,
    this.imagenes,
    this.userReaction,
    this.currentUserId,
  }) : super(key: key);

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  static const String _base = 'http://127.0.0.1:8000';
  late int _upvotes;
  late int _downvotes;
  bool _updatingUp = false;
  bool _updatingDown = false;
  int? _reactionId; // id en tabla Reaccion
  String? _reactionTipo; // 'upvote' | 'downvote' | null

  @override
  void initState() {
    super.initState();
    _upvotes = widget.report.upvotes;
    _downvotes = widget.report.downvotes;
    _reactionId = widget.userReaction?.id;
    _reactionTipo = widget.userReaction?.tipo;
  }

  Color _estadoColor(String s) {
    switch (s.toUpperCase()) {
      case 'ACTIVO':
        return Colors.orange;
      case 'RESUELTO':
      case 'CERRADO':
        return Colors.green;
      case 'EN PROCESO':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  Future<void> _vote({required bool up}) async {
    if (widget.currentUserId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Inicia sesión para votar')));
      return;
    }
    if (up && _updatingUp) return;
    if (!up && _updatingDown) return;

    final wasTipo = _reactionTipo; // estado previo
    final wasId = _reactionId;
    // Calcular nuevo estado y contadores optimistas
    String? newTipo = wasTipo;
    int upvotes = _upvotes;
    int downvotes = _downvotes;

    if (up) {
      if (wasTipo == 'upvote') {
        // toggle off upvote
        newTipo = null;
        upvotes = (_upvotes - 1).clamp(0, 1 << 31);
      } else if (wasTipo == 'downvote') {
        // cambiar down->up
        newTipo = 'upvote';
        upvotes = _upvotes + 1;
        downvotes = (_downvotes - 1).clamp(0, 1 << 31);
      } else {
        // no había reacción, crear upvote
        newTipo = 'upvote';
        upvotes = _upvotes + 1;
      }
    } else {
      if (wasTipo == 'downvote') {
        // toggle off downvote
        newTipo = null;
        downvotes = (_downvotes - 1).clamp(0, 1 << 31);
      } else if (wasTipo == 'upvote') {
        // cambiar up->down
        newTipo = 'downvote';
        upvotes = (_upvotes - 1).clamp(0, 1 << 31);
        downvotes = _downvotes + 1;
      } else {
        // no había reacción, crear downvote
        newTipo = 'downvote';
        downvotes = _downvotes + 1;
      }
    }

    setState(() {
      if (up)
        _updatingUp = true;
      else
        _updatingDown = true;
      _upvotes = upvotes;
      _downvotes = downvotes;
      _reactionTipo = newTipo;
    });

    try {
      // 1) Persistir reaccion
      if (newTipo == null) {
        // eliminar reaccion existente
        if (wasId != null) {
          final del = await http.delete(Uri.parse('$_base/Reacciones/$wasId'));
          if (del.statusCode < 200 || del.statusCode >= 300) {
            throw Exception('DELETE reaccion HTTP ${del.statusCode}');
          }
          _reactionId = null;
        }
      } else if (wasId == null) {
        // crear nueva
        final res = await http.post(
          Uri.parse('$_base/Reacciones'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'reporte_id': widget.report.id,
            'user_id': widget.currentUserId,
            'tipo': newTipo,
          }),
        );
        if (res.statusCode != 201) {
          throw Exception('POST reaccion HTTP ${res.statusCode}');
        }
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _reactionId = data['id'] as int?;
        _reactionTipo = newTipo;
      } else {
        // actualizar tipo existente
        final res = await http.patch(
          Uri.parse('$_base/Reacciones/$wasId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'tipo': newTipo}),
        );
        if (res.statusCode != 200) {
          throw Exception('PATCH reaccion HTTP ${res.statusCode}');
        }
        _reactionId = wasId;
        _reactionTipo = newTipo;
      }

      // 2) Persistir contadores del reporte
      final patchBody = <String, dynamic>{
        'cantidad_upvotes': _upvotes,
        'cantidad_downvotes': _downvotes,
      };
      final pr = await http.patch(
        Uri.parse('$_base/Reportes/${widget.report.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(patchBody),
      );
      if (pr.statusCode != 200) {
        throw Exception('PATCH reporte HTTP ${pr.statusCode}');
      }
    } catch (e) {
      // revertir a estado previo
      setState(() {
        _reactionTipo = wasTipo;
        _reactionId = wasId;
        _upvotes = widget.report.upvotes;
        _downvotes = widget.report.downvotes;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar tu voto: $e')),
      );
    } finally {
      setState(() {
        if (up)
          _updatingUp = false;
        else
          _updatingDown = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.report.veracidad;
    final vTxt = v == null ? '—' : '${v.toStringAsFixed(0)}%';
    final created = widget.report.createdAt;
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: R.br16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Título + estado
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.report.titulo.isEmpty
                        ? 'Reporte #${widget.report.id}'
                        : widget.report.titulo,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                MetaChip(
                  icon: Icons.info_outline,
                  label: widget.report.estado,
                  color: _estadoColor(widget.report.estado),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 18),
                const SizedBox(width: Spacing.sm),
                Flexible(
                  child: Text(
                    widget.userName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: Spacing.lg),
                if (created != null)
                  Text(
                    relativeTimeString(created),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                  ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Text(
              widget.report.descripcion.trim().isEmpty
                  ? 'Sin descripción'
                  : widget.report.descripcion.trim(),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Spacing.lg),
            if (widget.imagenes != null && widget.imagenes!.isNotEmpty) ...[
              SizedBox(
                height: 180,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.imagenes!.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: Spacing.md),
                  itemBuilder: (ctx, idx) {
                    final url = widget.imagenes![idx];
                    return GestureDetector(
                      onTap: () => _openImageViewer(
                        ctx,
                        widget.imagenes!,
                        startIndex: idx,
                      ),
                      child: ClipRRect(
                        borderRadius: R.br12,
                        child: Image.network(
                          url,
                          height: 180,
                          width: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => Container(
                            height: 180,
                            width: 220,
                            color: Colors.grey[200],
                            child: const Center(
                              child: Icon(Icons.broken_image, size: 40),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: Spacing.lg),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined, size: 18),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(
                    widget.report.direccion.isEmpty
                        ? 'Dirección no especificada'
                        : widget.report.direccion,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            Row(
              children: [
                const Icon(Icons.verified, size: 18),
                const SizedBox(width: Spacing.sm),
                Text('Veracidad: $vTxt'),
              ],
            ),
            if (v != null) ...[
              const SizedBox(height: Spacing.sm),
              ClipRRect(
                borderRadius: R.br12,
                child: LinearProgressIndicator(
                  value: (v.clamp(0, 100)) / 100.0,
                  minHeight: 8,
                ),
              ),
            ],
            const SizedBox(height: Spacing.lg),
            // Votos tipo Reddit
            Row(
              children: [
                // Upvote
                SizedBox(
                  height: 36,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _reactionTipo == 'upvote'
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.15)
                          : null,
                    ),
                    onPressed: _updatingUp ? null : () => _vote(up: true),
                    icon: _updatingUp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _reactionTipo == 'upvote'
                                ? Icons.thumb_up_alt
                                : Icons.thumb_up_alt_outlined,
                          ),
                    label: Text('$_upvotes'),
                  ),
                ),
                const SizedBox(width: Spacing.md),
                // Downvote
                SizedBox(
                  height: 36,
                  child: FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      foregroundColor: Colors.red[800],
                      backgroundColor: _reactionTipo == 'downvote'
                          ? Colors.red.withOpacity(0.12)
                          : null,
                    ),
                    onPressed: _updatingDown ? null : () => _vote(up: false),
                    icon: _updatingDown
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _reactionTipo == 'downvote'
                                ? Icons.thumb_down_alt
                                : Icons.thumb_down_alt_outlined,
                          ),
                    label: Text('$_downvotes'),
                  ),
                ),
              ],
            ),
            if (created != null) ...[
              const SizedBox(height: Spacing.sm),
              Text(
                'Creado ${relativeTimeString(created)}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void _openImageViewer(
  BuildContext context,
  List<String> urls, {
  int startIndex = 0,
}) {
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
  const _ImageViewer({Key? key, required this.urls, this.initialIndex = 0})
    : super(key: key);

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
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white70,
                  size: 64,
                ),
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
  const _ErrorView({Key? key, required this.message, required this.onRetry})
    : super(key: key);

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
            const Text(
              'Error cargando datos',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
